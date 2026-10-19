package me.saffer.sill.core

/**
 * Passes a session's stream callbacks to the screen showing it, and keeps what that screen needs if
 * it attaches late (Android starts an activity after the session has begun): the latest window list,
 * thumbnails, icons, app list, cursor, settings, pointer and the Mac's top-level menus, and the video since its last keyframe
 * (the format and every frame after it, at most [maxFrames]), replayed in order on attach.
 */
class ReplayingRouter(private val maxFrames: Int = 240) : SessionListener {
    private val lock = Any()
    private var target: SessionListener? = null
    private var list: WindowList? = null
    private val thumbnails = LinkedHashMap<Long, ByteArray>()
    private val icons = LinkedHashMap<String, ByteArray>()
    private var apps: List<AppInfo>? = null
    private var cursor: CursorShape? = null
    private var settings: HostSettingsState? = null
    private var pointer: Pair<Double, Double>? = null
    private var menuTop: MacMenu? = null
    private var format: ParameterSets? = null
    private val frames = ArrayList<Triple<ByteArray, Boolean, Double>>()

    /** The screen that shows the stream, or null; a new one gets everything kept first. */
    fun attach(t: SessionListener?): Unit = synchronized(lock) {
        target = t ?: return@synchronized
        list?.let(t::onWindowList)
        thumbnails.forEach { (id, j) -> t.onThumbnail(id, j) }
        icons.forEach { (id, p) -> t.onAppIcon(id, p) }
        apps?.let(t::onAppList)
        cursor?.let(t::onCursorShape)
        settings?.let(t::onHostSettings)
        menuTop?.let(t::onMacMenu)
        format?.let(t::onVideoFormat)
        frames.forEach { (au, key, ts) -> t.onFrame(au, key, ts) }
        t.onMacPointer(pointer)
    }

    fun detach(t: SessionListener) { synchronized(lock) { if (target === t) target = null } }

    /** A new session: nothing of the last one is replayed. */
    fun reset(): Unit = synchronized(lock) {
        list = null; thumbnails.clear(); icons.clear(); apps = null; cursor = null; settings = null; pointer = null; menuTop = null
        format = null; frames.clear()
    }

    override fun onWindowList(list: WindowList) {
        synchronized(lock) {
            this.list = list
            thumbnails.keys.retainAll(list.windows.map { it.id }.toSet())
            target?.onWindowList(list)
        }
    }
    override fun onThumbnail(windowID: Long, jpeg: ByteArray) { synchronized(lock) { thumbnails[windowID] = jpeg; target?.onThumbnail(windowID, jpeg) } }
    override fun onAppIcon(bundleID: String, png: ByteArray) { synchronized(lock) { icons[bundleID] = png; target?.onAppIcon(bundleID, png) } }
    override fun onAppList(apps: List<AppInfo>) { synchronized(lock) { this.apps = apps; target?.onAppList(apps) } }
    override fun onCursorShape(shape: CursorShape) { synchronized(lock) { cursor = shape; target?.onCursorShape(shape) } }
    override fun onHostSettings(state: HostSettingsState) { synchronized(lock) { settings = state; target?.onHostSettings(state) } }
    override fun onMacPointer(position: Pair<Double, Double>?) { synchronized(lock) { pointer = position; target?.onMacPointer(position) } }
    override fun onVideoFormat(sets: ParameterSets) { synchronized(lock) { format = sets; frames.clear(); target?.onVideoFormat(sets) } }
    override fun onFrame(annexB: ByteArray, keyframe: Boolean, timestamp: Double) {
        synchronized(lock) {
            if (keyframe) frames.clear()
            if (frames.size < maxFrames) frames.add(Triple(annexB, keyframe, timestamp))
            target?.onFrame(annexB, keyframe, timestamp)
        }
    }
    override fun onClipboard(text: String) { synchronized(lock) { target?.onClipboard(text) } }
    override fun onStats(stats: ClientStats) { synchronized(lock) { target?.onStats(stats) } }
    /** A top level (it has `menus`) is kept for a late screen; an answer goes only to the screen that asked. */
    override fun onMacMenu(menu: MacMenu) { synchronized(lock) { if (menu.menus != null) menuTop = menu; target?.onMacMenu(menu) } }
}
