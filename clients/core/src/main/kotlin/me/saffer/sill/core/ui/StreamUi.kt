package me.saffer.sill.core.ui

/**
 * The stream screen's state and what each control does to it: StreamScreen.swift's @State and its
 * actions (the Apps button, Keyboard, Settings and `setSettings`, the Aa ruler, a thumbnail's
 * lights, the menus), written once, so every platform opens, closes and restores in the same order.
 * The platform renders `state` and carries out the `Effect`s it is handed (the keyboard, a viewport
 * to send, a source to pick); it keeps no state of its own about what is open.
 */
class StreamUi(private val listener: (State, List<Effect>) -> Unit = { _, _ -> }) {
    data class State(
        val drawerOpen: Boolean = false,
        val settingsOpen: Boolean = false,
        /** The software keyboard is up, as this person asked (the Keyboard button lights). */
        val keyboardShown: Boolean = false,
        /** The keyboard was up when the panel opened: closing it puts it back. */
        val keyboardBeforeSettings: Boolean = false,
        /** The Aa ruler is unfolded (a finger holds Aa): the other buttons fade and take no touch. */
        val scaleOpen: Boolean = false,
        /** The Aa scale; null until first touched (the control shows 1×, the Mac window is left alone). */
        val textScale: Double? = null,
        /** The thumbnail whose lights are open. */
        val windowMenu: Long? = null,
        /** Modifiers latched by the key row until the next key, character or click uses them. */
        val latched: Long = 0,
        /** The Menus pull-down is open. */
        val menusOpen: Boolean = false,
        /** The pull-down closed the panel, which had taken the keyboard down: it comes back after. */
        val keyboardAfterMenus: Boolean = false,
    ) {
        /** Something is open over the stream that a tap elsewhere closes. */
        val overStream get() = drawerOpen || settingsOpen
    }

    sealed class Effect {
        data class Keyboard(val shown: Boolean) : Effect()
        /** The viewport changed (a new panel size or text scale): send it after Ui.viewportDebounce. */
        data object SendViewport : Effect()
        data object SelectDesktop : Effect()
    }

    var state = State()
        private set

    private fun set(s: State, vararg effects: Effect) {
        state = s
        listener(s, effects.toList())
    }

    fun tapApps() {
        val closed = closeSettings(state, restoreKeyboard = false)
        set(closed.first.copy(drawerOpen = !closed.first.drawerOpen), *closed.second.toTypedArray())
    }

    /** The drawer's dim, a pick in it, or Esc. */
    fun closeDrawer() { if (state.drawerOpen) set(state.copy(drawerOpen = false)) }

    fun tapKeyboard() {
        val (s, e) = closeSettings(state, restoreKeyboard = false)
        set(s.copy(keyboardShown = !s.keyboardShown), *(e + Effect.Keyboard(!s.keyboardShown)).toTypedArray())
    }

    /** The platform's keyboard came or went by itself (the system's hide key, a hardware keyboard). */
    fun keyboardChanged(shown: Boolean) { if (state.keyboardShown != shown) set(state.copy(keyboardShown = shown)) }

    fun tapDesktop() = set(state, Effect.SelectDesktop)

    fun tapSettings() = setSettings(!state.settingsOpen, restoreKeyboard = true)

    /** Done, Esc, a tap outside: the panel closes and the keyboard comes back if it was up. */
    fun closeSettings() = setSettings(false, restoreKeyboard = true)

    fun setSettings(open: Boolean, restoreKeyboard: Boolean) {
        if (open == state.settingsOpen) return
        if (open) {
            set(state.copy(settingsOpen = true, drawerOpen = false, windowMenu = null, scaleOpen = false,
                keyboardBeforeSettings = state.keyboardShown, keyboardShown = false), Effect.Keyboard(false))
        } else {
            val (s, e) = closeSettings(state, restoreKeyboard)
            set(s, *e.toTypedArray())
        }
    }

    private fun closeSettings(s: State, restoreKeyboard: Boolean): Pair<State, List<Effect>> {
        if (!s.settingsOpen) return s to emptyList()
        val back = restoreKeyboard && s.keyboardBeforeSettings
        return s.copy(settingsOpen = false, keyboardBeforeSettings = false, keyboardShown = if (back) true else s.keyboardShown) to
            (if (back) listOf(Effect.Keyboard(true)) else emptyList())
    }

    // The Aa ruler: unfold at the finger's touch, follow it, apply once on release.
    private var rulerStart = 1.0
    var rulerLive = 1.0
        private set

    fun rulerDown() {
        rulerStart = state.textScale ?: 1.0
        rulerLive = rulerStart
        set(state.copy(scaleOpen = true))
    }

    /** Returns true when the live value moved to another detent (a tick of haptic). */
    fun rulerMoved(dx: Double, pointsPerStep: Double): Boolean {
        val v = TextScale.dragged(rulerStart, dx, pointsPerStep)
        if (v == rulerLive) return false
        rulerLive = v
        listener(state, emptyList())
        return true
    }

    fun rulerUp() {
        val changed = (state.textScale ?: 1.0) != rulerLive
        val s = state.copy(scaleOpen = false, textScale = if (changed) rulerLive else state.textScale)
        if (changed) set(s, Effect.SendViewport) else set(s)
    }

    /** VoiceOver's adjustable action, the desktop's arrow keys over Aa. */
    fun stepScale(up: Boolean) {
        val v = TextScale.step(state.textScale, up)
        if (v != state.textScale) set(state.copy(textScale = v), Effect.SendViewport)
    }

    fun openWindowMenu(id: Long) { if (state.windowMenu != id) set(state.copy(windowMenu = id)) }
    fun closeWindowMenu() { if (state.windowMenu != null) set(state.copy(windowMenu = null)) }

    /** The window list changed: a thumbnail that went takes its lights with it. */
    fun windowsChanged(ids: Set<Long>) { state.windowMenu?.let { if (it !in ids) closeWindowMenu() } }

    fun latch(latched: Long) { if (latched != state.latched) set(state.copy(latched = latched)) }

    fun menusOpened() {
        val after = state.settingsOpen && state.keyboardBeforeSettings
        val (s, e) = closeSettings(state, restoreKeyboard = false)
        set(s.copy(windowMenu = null, drawerOpen = false, menusOpen = true, keyboardAfterMenus = after), *e.toTypedArray())
    }

    fun menusClosed() {
        val back = state.keyboardAfterMenus
        val s = state.copy(menusOpen = false, keyboardAfterMenus = false, keyboardShown = state.keyboardShown || back)
        if (back) set(s, Effect.Keyboard(true)) else set(s)
    }

    /** The session ended: nothing of it is kept but the text scale, as the iOS screen keeps it. */
    fun reset() = set(State(textScale = state.textScale))
}
