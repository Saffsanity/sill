package me.saffer.sill.core.ui

import me.saffer.sill.core.FetchMenu
import me.saffer.sill.core.MacMenu
import me.saffer.sill.core.MacMenuItem
import me.saffer.sill.core.PressMenuItem
import me.saffer.sill.core.SafeText

/**
 * One connection's view of the Mac's menus (kinds 24, 25 and 27): the iOS app's MacMenuState
 * (iOSClient/MacMenuState.swift, docs/menu-bar-plan.md §7.2), rule for rule. Pure: the apps own one
 * per session on their UI thread through [MacMenus], which runs the completions it hands back.
 *
 * Each opened menu is one completion, known here by a key, settled exactly once: by the answer to its
 * fetch, at once when nothing may be asked, by the timeout, or by the end of the connection.
 *
 * 1. Nothing before the first top level ("Not connected.").
 * 2. A top level replaces the one before; a new version settles every waiting fetch of another
 *    version with "The menus changed. Open the menu again.".
 * 3. One fetch per menu: opening one whose fetch waits joins it; the kind 27 carries the title shown.
 * 4. An answer settles only the fetch with its token; an unknown token is dropped.
 * 5. An answer of another version than the fetch's, or a row of an older version, is "changed".
 * 6. `expire` settles a fetch that waited max(4 s, 4 × the worst round trip): "‹Mac› didn’t answer…".
 * 7. Stale: nothing fetched; the note alone, or rows all disabled under it.
 * 8. Presses: never a disabled row, never before a top level; refused here while stale; a
 *    `pressed: false` answer is a refusal to tell the user.
 * 9. `reset` settles everything with "Not connected."; `connectionReplaced` settles the fetches.
 * 10. `sections`: separators split sections (leading, trailing, doubled dropped), untitled items
 *     dropped, "-"/"–" mixed, any other mark on, `more` adds "‹n› more on the Mac", nothing gives
 *     "No items".
 * 11. A top-level menu asks by what it showed (`barMenuID`).
 */
class MacMenuState {
    class Row(val kind: Kind, val id: String? = null, val title: String, val key: String? = null, val enabled: Boolean = true,
              val mark: Mark = Mark.Off, val version: Int? = null) {
        enum class Kind { Item, Submenu, Note }
        enum class Mark { Off, On, Mixed }
        override fun equals(other: Any?) = other is Row && kind == other.kind && id == other.id && title == other.title && key == other.key &&
            enabled == other.enabled && mark == other.mark && version == other.version
        override fun hashCode() = listOf(kind, id, title, key, enabled, mark, version).hashCode()
        override fun toString() = "Row($kind, $id, $title, key=$key, enabled=$enabled, $mark, v$version)"
        companion object { fun note(text: String) = Row(Kind.Note, title = text, enabled = false) }
    }

    sealed class Content {
        data class Sections(val sections: List<List<Row>>, val more: Int) : Content()
        data class Message(val text: String) : Content()
    }

    data class Done(val key: Int, val content: Content)

    data class Refusal(val title: String, val id: String, val note: String, val byMac: Boolean) {
        val announcement get() = "Couldn’t choose $title. $note"
    }

    sealed class Fetch {
        data class Send(val fetch: FetchMenu) : Fetch()
        object Joined : Fetch()
        data class Settled(val content: Content) : Fetch()
    }

    sealed class Press {
        data class Send(val press: PressMenuItem) : Press()
        data class Refused(val refusal: Refusal) : Press()
    }

    data class Top(val version: Int?, val app: String?, val menus: List<Row>, val stale: Boolean, val note: String?)

    data class Received(val done: List<Done>, val topChanged: Boolean, val refusal: Refusal?)

    var version: Int? = null; private set
    var app: String? = null; private set
    var menus: List<Row> = emptyList(); private set
    var stale = false; private set
    var note: String? = null; private set

    /** Whether the Menus button shows: menus, or a note to show (no Accessibility on the Mac). */
    val hasMenus get() = menus.isNotEmpty() || note != null
    val top get() = Top(version, app, menus, stale, note)

    private class Waiting(val id: String, val title: String, val version: Int, val token: Int, val keys: MutableList<Int>, val sentAt: Double)
    private val waiting = ArrayList<Waiting>()
    private class Choice(val token: Int, val id: String, val title: String)
    private val choices = ArrayList<Choice>()

    val oldestWait: Double? get() = waiting.minOfOrNull { it.sentAt }
    val waitingKeys: List<Int> get() = waiting.flatMap { it.keys }

    fun receive(m: MacMenu, now: Double): Received {
        val items = m.menus
        if (items != null) {
            val v = m.version ?: return Received(emptyList(), false, null)
            val before = top
            version = v
            app = clean(m.app, SafeText.LABEL_LIMIT)
            stale = m.stale == true
            note = clean(m.note, NOTE_LIMIT)
            if (stale && note == null) note = "${app ?: "The app"} isn’t responding."
            menus = topRows(items, v)
            val done = ArrayList<Done>()
            waiting.removeAll { w -> if (w.version == version) false else { w.keys.forEach { done.add(Done(it, Content.Message(CHANGED))) }; true } }
            return Received(done, top != before, null)
        }
        val token = m.answering ?: return Received(emptyList(), false, null)
        waiting.indexOfFirst { it.token == token }.takeIf { it >= 0 }?.let { i ->
            val w = waiting.removeAt(i)
            val content = if (m.version != w.version) Content.Message(CHANGED) else {
                val more = maxOf(0, m.more ?: 0)
                Content.Sections(sections(m.items ?: emptyList(), m.stale == true, m.note, more, w.version), more)
            }
            return Received(w.keys.map { Done(it, content) }, false, null)
        }
        choices.indexOfFirst { it.token == token }.takeIf { it >= 0 }?.let { i ->
            val c = choices.removeAt(i)
            if (m.pressed != false) return Received(emptyList(), false, null)
            return Received(emptyList(), false, Refusal(c.title, c.id, clean(m.note, NOTE_LIMIT) ?: CHANGED, true))
        }
        return Received(emptyList(), false, null)
    }

    fun fetch(id: String, title: String, asked: Int?, key: Int, token: Int, now: Double): Fetch {
        val current = version ?: return Fetch.Settled(Content.Message(NOT_CONNECTED))
        if (asked != current) return Fetch.Settled(Content.Message(CHANGED))
        if (stale) return Fetch.Settled(Content.Sections(sections(emptyList(), true, note, 0, current), 0))
        waiting.firstOrNull { it.id == id && it.title == title && it.version == current }?.let { it.keys.add(key); return Fetch.Joined }
        waiting.add(Waiting(id, title, current, token, mutableListOf(key), now))
        return Fetch.Send(FetchMenu(current, id, title, token))
    }

    fun barMenuID(builtID: String, title: String): String? {
        if (version == null) return null
        if (menus.any { it.id == builtID && it.title == title }) return builtID
        return menus.firstOrNull { it.title == title }?.id
    }

    fun press(row: Row, token: Int): Press? {
        if (version == null || row.kind != Row.Kind.Item || !row.enabled) return null
        val id = row.id ?: return null
        val v = row.version ?: return null
        if (stale) return Press.Refused(Refusal(row.title, id, note ?: CHANGED, false))
        choices.add(Choice(token, id, row.title))
        while (choices.size > MAX_CHOICES) choices.removeAt(0)
        return Press.Send(PressMenuItem(v, id, row.title, token))
    }

    fun expire(now: Double, timeout: Double, mac: String): List<Done> {
        val done = ArrayList<Done>()
        waiting.removeAll { w -> if (now - w.sentAt < timeout) false else { w.keys.forEach { done.add(Done(it, Content.Message(noAnswer(mac)))) }; true } }
        return done
    }

    fun reset(): List<Done> {
        val done = waitingKeys.map { Done(it, Content.Message(NOT_CONNECTED)) }
        version = null; app = null; menus = emptyList(); stale = false; note = null; waiting.clear(); choices.clear()
        return done
    }

    fun connectionReplaced(): List<Done> {
        val done = waitingKeys.map { Done(it, Content.Message(CHANGED)) }
        waiting.clear(); choices.clear()
        return done
    }

    companion object {
        const val CHANGED = "The menus changed. Open the menu again."
        const val NOT_CONNECTED = "Not connected."
        const val NO_ITEMS = "No items"
        const val MAX_MENUS = 32
        const val TITLE_LIMIT = 100
        const val KEY_LIMIT = 16
        const val NOTE_LIMIT = 300
        const val MAX_CHOICES = 16
        fun noAnswer(mac: String) = "${mac.ifEmpty { "The Mac" }} didn’t answer. Open the menu again."
        fun moreOnTheMac(count: Int) = "$count more on the Mac"

        fun sections(items: List<MacMenuItem>, stale: Boolean, note: String?, more: Int, version: Int?): List<List<Row>> {
            val out = ArrayList<List<Row>>()
            clean(note, NOTE_LIMIT)?.let { out.add(listOf(Row.note(it))) }
            var section = ArrayList<Row>()
            for (item in items) {
                if (item.separator == true) { if (section.isNotEmpty()) out.add(section); section = ArrayList(); continue }
                val title = clean(item.title, TITLE_LIMIT) ?: continue
                val kind = if (item.submenu == true) Row.Kind.Submenu else Row.Kind.Item
                section.add(Row(kind, item.id, title, if (kind == Row.Kind.Item) clean(item.key, KEY_LIMIT) else null,
                    item.enabled != false && !stale && item.id != null, mark(item.mark), version))
            }
            if (section.isNotEmpty()) out.add(section)
            if (more > 0) out.add(listOf(Row.note(moreOnTheMac(more))))
            if (out.isEmpty()) out.add(listOf(Row.note(NO_ITEMS)))
            return out
        }

        fun mark(raw: String?): Row.Mark {
            val m = clean(raw, 1) ?: return Row.Mark.Off
            return if (m == "-" || m == "–") Row.Mark.Mixed else Row.Mark.On
        }

        fun topRows(items: List<MacMenuItem>, version: Int?): List<Row> {
            val rows = ArrayList<Row>()
            val ids = HashSet<String>()
            for (item in items) {
                if (rows.size >= MAX_MENUS) break
                val id = item.id ?: continue
                if (!isTopID(id) || id in ids) continue
                val title = clean(item.title, TITLE_LIMIT) ?: continue
                ids.add(id)
                rows.add(Row(Row.Kind.Submenu, id, title, enabled = item.enabled != false, version = version))
            }
            return rows
        }

        fun isTopID(id: String) = id.length in 1..4 && id[0] != '0' && id.all { it in '0'..'9' }

        fun clean(text: String?, limit: Int): String? = text?.let { SafeText.label(it, limit) }?.ifEmpty { null }
    }
}

/**
 * The menus of one session, for a UI on one thread (Android's main looper, Swing's event thread):
 * [MacMenuState] with the tokens, the timeout's look and the sends. Every call, and every callback,
 * is on that thread; [post] and [postDelayed] are its scheduler, [now] its monotonic clock.
 */
class MacMenus(private val mac: String, private val send: (Any) -> Unit, private val worstRtt: () -> Double?,
               private val now: () -> Double, private val postDelayed: (Double, () -> Unit) -> Unit) {
    val state = MacMenuState()
    var onTop: (MacMenuState.Top) -> Unit = {}
    var onRefusal: (MacMenuState.Refusal) -> Unit = {}
    private val completions = HashMap<Int, (MacMenuState.Content) -> Unit>()
    private var nextKey = 1
    private var nextToken = 1
    private var timerArmed = false

    /** max(4 s, 4 × the worst recent round trip), as the iOS app waits. */
    val timeout get() = maxOf(4.0, 4 * (worstRtt() ?: 0.0))

    fun receive(m: MacMenu) {
        val r = state.receive(m, now())
        settle(r.done)
        if (r.topChanged) onTop(state.top)
        r.refusal?.let(onRefusal)
    }

    /** A menu opened: [done] gets its rows once (at once, on the answer, at the timeout or the end). */
    fun open(row: MacMenuState.Row, done: (MacMenuState.Content) -> Unit) {
        val id = row.id ?: return done(MacMenuState.Content.Message(MacMenuState.CHANGED))
        val asked = if (row.kind == MacMenuState.Row.Kind.Submenu && MacMenuState.isTopID(id)) {
            // Rule 11: a top-level menu asks by what it showed.
            val now = state.barMenuID(id, row.title) ?: return done(MacMenuState.Content.Message(MacMenuState.CHANGED))
            return openId(now, row.title, state.version, done)
        } else row.version
        openId(id, row.title, asked, done)
    }

    private fun openId(id: String, title: String, asked: Int?, done: (MacMenuState.Content) -> Unit) {
        val key = nextKey++
        when (val f = state.fetch(id, title, asked, key, nextToken, now())) {
            is MacMenuState.Fetch.Settled -> done(f.content)
            MacMenuState.Fetch.Joined -> completions[key] = done
            is MacMenuState.Fetch.Send -> { nextToken++; completions[key] = done; send(f.fetch); armTimer() }
        }
    }

    fun choose(row: MacMenuState.Row) {
        when (val p = state.press(row, nextToken) ?: return) {
            is MacMenuState.Press.Send -> { nextToken++; send(p.press) }
            is MacMenuState.Press.Refused -> onRefusal(p.refusal)
        }
    }

    fun reset() { settle(state.reset()); onTop(state.top) }
    fun connectionReplaced() = settle(state.connectionReplaced())

    private fun settle(done: List<MacMenuState.Done>) { for (d in done) completions.remove(d.key)?.invoke(d.content) }

    private fun armTimer() {
        if (timerArmed) return
        val oldest = state.oldestWait ?: return
        timerArmed = true
        postDelayed(maxOf(0.05, oldest + timeout - now())) {
            timerArmed = false
            settle(state.expire(now(), timeout, mac))
            armTimer()
        }
    }
}
