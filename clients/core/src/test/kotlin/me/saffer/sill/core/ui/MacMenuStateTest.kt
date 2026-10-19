package me.saffer.sill.core.ui

import me.saffer.sill.core.Clock
import me.saffer.sill.core.Identity
import me.saffer.sill.core.FetchMenu
import me.saffer.sill.core.Kind
import me.saffer.sill.core.MacMenu
import me.saffer.sill.core.MacMenuItem
import me.saffer.sill.core.ModelHost
import me.saffer.sill.core.PressMenuItem
import me.saffer.sill.core.SessionListener
import me.saffer.sill.core.SillSession
import me.saffer.sill.core.SillTls
import me.saffer.sill.core.Trust
import me.saffer.sill.core.Viewport
import me.saffer.sill.core.WindowList
import me.saffer.sill.core.JsonObj
import me.saffer.sill.core.ui.MacMenuState.Content
import me.saffer.sill.core.ui.MacMenuState.Row
import java.util.concurrent.CountDownLatch
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** The iOS app's MacMenuState rules (Tests/checks/menu-state), as the Kotlin port keeps them. */
class MacMenuStateTest {
    private fun top(v: Int, vararg titles: String) = MacMenu(version = v, app = "Code", menus = titles.mapIndexed { i, t -> MacMenuItem("${i + 1}", t, submenu = true) })

    @Test
    fun rulesOneToFive() {
        val s = MacMenuState()
        // 1: nothing before a top level.
        assertEquals(MacMenuState.Fetch.Settled(Content.Message("Not connected.")), s.fetch("2", "File", 1, 1, 1, 0.0))
        assertTrue(s.receive(top(1, "Code", "File"), 0.0).topChanged)
        assertTrue(s.hasMenus)
        // 3: one fetch per menu; the second opening joins it.
        val f = assertIs<MacMenuState.Fetch.Send>(s.fetch("2", "File", 1, 10, 7, 0.0))
        assertEquals(FetchMenu(1, "2", "File", 7), f.fetch)
        assertEquals(MacMenuState.Fetch.Joined, s.fetch("2", "File", 1, 11, 8, 0.0))
        // 4: an unknown token settles nothing.
        assertTrue(s.receive(MacMenu(version = 1, answering = 99, items = listOf()), 0.0).done.isEmpty())
        // The answer settles both keys with its sections.
        val r = s.receive(MacMenu(version = 1, answering = 7, items = listOf(MacMenuItem("2.0", "Save", key = "⌘S"))), 0.0)
        assertEquals(listOf(10, 11), r.done.map { it.key })
        assertEquals(Content.Sections(listOf(listOf(Row(Row.Kind.Item, "2.0", "Save", "⌘S", version = 1))), 0), r.done[0].content)
        // 5: a row of an older version is "changed", unasked; 2: a new tree settles the waiting fetch of the old one.
        assertIs<MacMenuState.Fetch.Send>(s.fetch("1", "Code", 1, 12, 9, 0.0))
        val r2 = s.receive(top(2, "Code", "File"), 0.0)
        assertEquals(listOf(MacMenuState.Done(12, Content.Message(MacMenuState.CHANGED))), r2.done)
        assertEquals(MacMenuState.Fetch.Settled(Content.Message(MacMenuState.CHANGED)), s.fetch("2.4", "Open Recent", 1, 13, 10, 0.0))
        // An answer of another version than its fetch's.
        assertIs<MacMenuState.Fetch.Send>(s.fetch("2", "File", 2, 14, 11, 0.0))
        assertEquals(Content.Message(MacMenuState.CHANGED), s.receive(MacMenu(version = 3, answering = 11, items = listOf()), 0.0).done.single().content)
    }

    @Test
    fun timeoutStaleAndPresses() {
        val s = MacMenuState()
        s.receive(top(1, "Code", "File"), 0.0)
        s.fetch("2", "File", 1, 1, 1, 0.0)
        assertTrue(s.expire(3.9, 4.0, "Mac mini").isEmpty())
        assertEquals(Content.Message("Mac mini didn’t answer. Open the menu again."), s.expire(4.0, 4.0, "Mac mini").single().content)
        val save = Row(Row.Kind.Item, "2.6", "Save", version = 1)
        assertEquals(MacMenuState.Press.Send(PressMenuItem(1, "2.6", "Save", 5)), s.press(save, 5))
        assertNull(s.press(Row(Row.Kind.Item, "2.10", "Revert", enabled = false, version = 1), 6))
        assertEquals("Couldn’t choose Save. Not now.", s.receive(MacMenu(version = 1, answering = 5, pressed = false, note = "Not now."), 0.0).refusal?.announcement)
        // 7: stale: nothing fetched, presses refused here.
        s.receive(MacMenu(version = 2, app = "Code", menus = listOf(MacMenuItem("2", "File", submenu = true)), stale = true), 0.0)
        assertEquals("Code isn’t responding.", s.note)
        val st = assertIs<MacMenuState.Fetch.Settled>(s.fetch("2", "File", 2, 2, 2, 0.0))
        assertEquals(listOf(listOf(Row.note("Code isn’t responding."))), (st.content as Content.Sections).sections)
        assertIs<MacMenuState.Press.Refused>(s.press(Row(Row.Kind.Item, "2.6", "Save", version = 2), 7))
        // 9: reset.
        s.receive(top(3, "File"), 0.0); s.fetch("1", "File", 3, 3, 3, 0.0)
        assertEquals(listOf(MacMenuState.Done(3, Content.Message("Not connected."))), s.reset())
        assertTrue(!s.hasMenus)
    }

    @Test
    fun sectionsAndTopRows() {
        val items = listOf(MacMenuItem("x.0", separator = true), MacMenuItem("x.1", "A"), MacMenuItem("x.2", separator = true), MacMenuItem("x.3", separator = true),
            MacMenuItem("x.4", "B", mark = "✓"), MacMenuItem("x.5", "C", mark = "–"), MacMenuItem("x.6", null), MacMenuItem("x.7", separator = true))
        val secs = MacMenuState.sections(items, false, null, 3, 1)
        assertEquals(listOf("A"), secs[0].map { it.title })
        assertEquals(listOf(Row.Mark.On, Row.Mark.Mixed), secs[1].map { it.mark })
        assertEquals(Row.note("3 more on the Mac"), secs[2].single())
        assertEquals(listOf(listOf(Row.note("No items"))), MacMenuState.sections(emptyList(), false, null, 0, 1))
        val tops = MacMenuState.topRows(listOf(MacMenuItem("0", "Apple"), MacMenuItem("1", "Code"), MacMenuItem("1", "Dup"), MacMenuItem("01", "Zero"),
            MacMenuItem("12345", "Long"), MacMenuItem("2.1", "Deep"), MacMenuItem("3", "")), 1)
        assertEquals(listOf("Code"), tops.map { it.title })
        // 11: a bar menu asks by what it showed.
        val s = MacMenuState(); s.receive(top(1, "Code", "File"), 0.0)
        assertEquals("2", s.barMenuID("2", "File")); assertEquals("2", s.barMenuID("5", "File")); assertNull(s.barMenuID("2", "Edit"))
    }

    /** End to end against the model Mac: the subscription at the first window list, a menu, a choice. */
    @Test
    fun subscribeOpenAndChoose() {
        ModelHost().use { host ->
            host.requirePairing = false
            val menus = LinkedBlockingQueue<MacMenu>()
            val connected = CountDownLatch(1)
            val listener = object : SessionListener {
                override fun onConnected(list: WindowList) { connected.countDown() }
                override fun onMacMenu(menu: MacMenu) { menus.add(menu) }
            }
            val c = SillTls.dial(host.address, Identity.generate(), SillTls.SESSION_ALPN, Trust.Pinned(host.fingerprint))
            val session = SillSession(c, me.saffer.sill.core.ClientInfo("0.6.0", "7", "Test (JVM)", "PC", "JVM", "test-pc"), listener, Clock.System)
            session.start(Viewport(800.0, 600.0, null, fps = 60))
            assertTrue(connected.await(5, TimeUnit.SECONDS))
            // One thread stands in for the UI's: everything through a queue.
            val ui = LinkedBlockingQueue<() -> Unit>()
            val m = MacMenus("Mac", send = { p ->
                when (p) { is FetchMenu -> session.fetchMenu(p); is PressMenuItem -> session.pressMenuItem(p) }
            }, worstRtt = { session.worstRtt }, now = { Clock.System.mono() }, postDelayed = { _, f -> ui.add(f) })
            var shown: MacMenuState.Top? = null
            m.onTop = { shown = it }
            m.receive(assertNotNull(menus.poll(5, TimeUnit.SECONDS), "the top level"))
            assertEquals(listOf("Code", "File", "Edit", "Selection", "View", "Go", "Run", "Terminal", "Window", "Help"), shown?.menus?.map { it.title })
            var got: Content? = null
            m.open(shown!!.menus[1]) { got = it }
            m.receive(assertNotNull(menus.poll(5, TimeUnit.SECONDS), "File's items"))
            val rows = assertIs<Content.Sections>(got).sections.flatten()
            assertEquals("Save", rows.first { it.id == "2.6" }.title)
            assertEquals("⇧⌘S", rows.first { it.id == "2.7" }.key)
            assertEquals(Row.Mark.On, rows.first { it.id == "2.8" }.mark)
            m.choose(rows.first { it.id == "2.6" })
            val press = assertNotNull(host.latestSession()!!.presses.poll(5, TimeUnit.SECONDS))
            assertEquals(PressMenuItem(1, "2.6", "Save", press.token), press)
            assertTrue(host.violations.isEmpty(), "${host.violations}")
            assertEquals(Kind.FETCH_MENU, host.latestSession()!!.all.first { it.kind == Kind.FETCH_MENU }.kind)
            assertNull(FetchMenu.fromJson(JsonObj.parse(host.latestSession()!!.all.first { it.kind == Kind.FETCH_MENU }.payload)).id, "the subscription has no id")
            session.close()
        }
    }
}
