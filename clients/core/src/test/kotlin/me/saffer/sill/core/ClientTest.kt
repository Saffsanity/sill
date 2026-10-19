package me.saffer.sill.core

import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * The whole client against the model Mac: a row, the ask, the code, the pinned session, a reconnect
 * after the Mac quits, a removal, pairing by link and by a typed address, and the remote dial.
 */
class ClientTest {
    private val info = ClientInfo("0.6.0", "7", "Test (JVM)", "PC", "JVM", "test-pc")

    class UI : ClientListener {
        val rows = LinkedBlockingQueue<List<MacRow>>()
        val status = CopyOnWriteArrayList<String?>()
        val prompts = LinkedBlockingQueue<PairingPrompt>()
        val started = LinkedBlockingQueue<SillSession>()
        val ended = LinkedBlockingQueue<GoodbyePolicy.Outcome>()
        @Volatile var lastRows: List<MacRow> = emptyList()
        override fun onRows(rows: List<MacRow>) { lastRows = rows; this.rows.add(rows) }
        override fun onStatus(text: String?) { status.add(text) }
        override fun onPairingPrompt(prompt: PairingPrompt) { prompts.add(prompt) }
        override fun onSessionStarted(session: SillSession, mac: String) { started.add(session) }
        override fun onSessionEnded(outcome: GoodbyePolicy.Outcome) { ended.add(outcome) }
    }

    private fun client(ui: UI, store: KeyValueStore = KeyValueStore.Memory()) =
        SillClient(info, store, IdentityStore.InKeyValue(store), ui, object : SessionListener {})

    private fun <T> LinkedBlockingQueue<T>.next(s: Long = 10): T = assertNotNull(poll(s, TimeUnit.SECONDS), "timed out")

    @Test
    fun askCodeSessionReconnectRemove() {
        ModelHost().use { host ->
            val ui = UI()
            val store = KeyValueStore.Memory()
            val c = client(ui, store)
            c.setFound(listOf(host.found()))
            val row = ui.lastRows.single()
            assertEquals("Not paired", row.word)
            assertIs<HomeDial.Decision.Ask>(row.decision)

            // A tap asks; the Mac shows a code; the code pairs; the session starts pinned.
            c.connect(row)
            val prompt = ui.prompts.next()
            assertEquals(PairRequest.ASK, host.pairRequests.last().method)
            val code = assertNotNull(host.code)
            // A typo is caught here, and a wrong code costs a try.
            c.submitCode(prompt, code.dropLast(1) + ((code.last() - '0' + 1) % 10)) {}
            Thread.sleep(300)
            assertTrue(ui.status.any { it == PairingWords.codeProblem(PairingCode.Problem.TYPO) }, "${ui.status}")
            c.submitCode(prompt, code)
            val session = ui.started.next(20)
            val hs = assertNotNull(host.latestSession())
            assertTrue(host.violations.isEmpty(), "${host.violations}")
            assertEquals(1, host.paired.size)
            val saved = c.saved.all.single()
            assertEquals(host.macID, saved.macID)
            assertEquals("code", saved.method)
            // Saved, and recognized by the tag, the row is a paired Mac now (on loopback, no way-in word).
            c.setFound(listOf(host.found("Model Mac (2)")))
            val paired = ui.lastRows.single()
            assertIs<HomeDial.Decision.Pinned>(paired.decision)
            assertNull(paired.word)
            assertEquals(host.macName, paired.name)
            // The same store gives the same identity and saved Mac at the next launch.
            assertEquals(c.identity.fingerprint.toList(), client(UI(), store).identity.fingerprint.toList())

            // The Mac quits: its words, and a reconnect while its row stays listed.
            val sessionsBefore = host.sessions.size
            hs.goodbye(Goodbye(Goodbye.QUIT))
            val out = ui.ended.next()
            assertEquals("Model Mac quit Sill. This PC reconnects when it’s back.", out.text)
            assertTrue(out.reconnect)
            ui.started.next(20)
            val until = System.nanoTime() + 5_000_000_000
            while (host.sessions.size <= sessionsBefore && System.nanoTime() < until) Thread.sleep(20)
            assertTrue(host.sessions.size > sessionsBefore)

            // Removed on the Mac: no reconnect, and the row asks to pair again.
            host.remove(c.identity.fingerprint)
            val removed = ui.ended.next()
            assertTrue(!removed.reconnect)
            assertTrue(c.saved.all.single().revoked)
            c.setFound(listOf(host.found()))
            assertEquals("Not paired", ui.lastRows.single().word)
            assertIs<HomeDial.Decision.Ask>(ui.lastRows.single().decision)
            session.close()
            c.stop()
        }
    }

    @Test
    fun removedWhileAwayReadsAsPairAgain() {
        // Paired, then removed on the Mac while this client was not connected: its next dial is
        // refused, and the row asks to pair again instead of retrying for ever.
        ModelHost().use { host ->
            val ui = UI()
            val c = client(ui)
            val result = LinkedBlockingQueue<PairOutcome>()
            c.pairWithLink(host.link()) { result.add(it) }
            assertIs<PairOutcome.Paired>(result.next(20))
            ui.started.next(20)
            c.disconnect()
            ui.ended.next()
            host.paired.clear()
            c.setFound(listOf(host.found()))
            c.connect(ui.lastRows.single())
            val until = System.nanoTime() + 10_000_000_000
            // The client saves the Mac as revoked, then publishes its rows: wait for both.
            while ((c.saved.all.single().revoked.not() || ui.lastRows.single().word != "Not paired") && System.nanoTime() < until) Thread.sleep(50)
            assertTrue(c.saved.all.single().revoked)
            assertEquals("Not paired", ui.lastRows.single().word)
            c.stop()
        }
    }

    @Test
    fun anOpenDoorTakesAnyKey() {
        ModelHost().use { host ->
            host.requirePairing = false
            val ui = UI()
            val c = client(ui)
            c.setFound(listOf(host.found()))
            assertEquals(HomeDial.Decision.AnyKey, ui.lastRows.single().decision)
            c.connect(ui.lastRows.single())
            ui.started.next()
            assertTrue(c.saved.all.isEmpty())
            c.stop()
        }
    }

    @Test
    fun pairByLinkThenRemoteDial() {
        ModelHost().use { host ->
            val ui = UI()
            val c = client(ui)
            val result = LinkedBlockingQueue<PairOutcome>()
            c.pairWithLink(host.link()) { result.add(it) }
            val out = result.next(20)
            assertIs<PairOutcome.Paired>(out, "$out")
            assertEquals("qr", c.saved.all.single().method)
            // Not on the network: the row is the Mac's remote one, dialed at kind 18's address.
            val deadline = System.nanoTime() + 10_000_000_000
            while (c.saved.all.single().addresses.isEmpty() && System.nanoTime() < deadline) Thread.sleep(50)
            c.disconnect()
            val remote = c.rows().single()
            assertEquals("Remote", remote.word)
            c.connect(remote)
            ui.started.next(20)
            ui.started.next(20)
            c.stop()
        }
    }

    /** The review's finding 9: a dial that hangs first never holds the one that connected. */
    @Test
    fun aHungFirstRemoteAddressDoesNotHoldTheWinner() {
        ModelHost().use { host ->
            // Takes the TCP connection and never says a word: the TLS dial waits out its 10 s.
            val silent = java.net.ServerSocket(0, 50, java.net.InetAddress.getLoopbackAddress())
            val held = java.util.concurrent.CopyOnWriteArrayList<java.net.Socket>()
            Thread { try { while (true) held.add(silent.accept()) } catch (_: Exception) {} }.apply { isDaemon = true; start() }
            try {
                val ui = UI()
                val c = client(ui)
                val result = LinkedBlockingQueue<PairOutcome>()
                c.pairWithLink(host.link()) { result.add(it) }
                assertIs<PairOutcome.Paired>(result.next(20))
                ui.started.next(20)
                val deadline = System.nanoTime() + 10_000_000_000
                while (c.saved.all.single().addresses.isEmpty() && System.nanoTime() < deadline) Thread.sleep(50)
                c.disconnect()
                val mac = c.saved.all.single()
                c.saved.update(mac.macID) { it.copy(lastWorked = "127.0.0.1:${silent.localPort}") }
                assertEquals(java.net.InetSocketAddress(java.net.InetAddress.getLoopbackAddress(), silent.localPort), c.remoteTargets(c.saved.all.single()).first())
                val start = System.nanoTime()
                c.connect(c.rows().single())
                ui.started.next(20)
                val took = (System.nanoTime() - start) / 1e9
                assertTrue(took < 5, "the session waited ${"%.1f".format(took)} s for the hung dial")
                c.stop()
            } finally { silent.close(); held.forEach { it.close() } }
        }
    }

    @Test
    fun addByTypedAddressAndCode() {
        ModelHost().use { host ->
            val ui = UI()
            val c = client(ui)
            val code = host.openWindow()
            val result = LinkedBlockingQueue<PairOutcome>()
            c.addByAddress("127.0.0.1:${host.port}", code) { result.add(it) }
            assertIs<PairOutcome.Paired>(result.next(30))
            assertEquals(listOf("127.0.0.1:${host.port}"), c.saved.all.single().typedAddresses)
            ui.started.next(20)
            // Refusals word themselves: a bad address, a closed window.
            c.addByAddress("1.2.3", "482913557208") { result.add(it) }
            assertEquals("That isn’t a complete IPv4 address (four numbers 0–255).", (result.next() as PairOutcome.Failed).words)
            c.stop()
        }
    }

    @Test
    fun goodbyeWords() {
        fun o(r: String?, saved: Boolean = true, msg: String? = null, rc: Boolean? = null) =
            GoodbyePolicy.outcome(r?.let { Goodbye(it, msg, if (it == "update") "1.2" else null, rc) }, "Mac", "PC", saved)
        assertEquals("Mac disconnected. Sill will reconnect when it can reach it.", o(null).text)
        assertEquals("Mac disconnected. It will reconnect when the host is back.", o(null, saved = false).text)
        assertEquals(false, o("removed").reconnect)
        assertEquals("Mac is already serving 8 devices.", o("busy").text)
        assertEquals("Update Sill on this PC to keep using Mac. It needs version 1.2 or later.", o("update").text)
        assertEquals(false, o("update").reconnect)
        assertEquals("New words", o("later", msg = "New\nwords").text)
        assertEquals(true, o("later", rc = true).reconnect)
        assertEquals("Mac closed the connection. Tap it to try again.", o("later").text)
        assertEquals(listOf(true to null, false to 105.0, true to null), listOf(Redial.next(0, null, 100.0), Redial.next(1, 100.0, 101.0), Redial.next(4, 70.0, 100.0)))
        assertEquals(false to null, Redial.next(12, 0.0, 1000.0))
    }
}
