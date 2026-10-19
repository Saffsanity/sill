package me.saffer.sill.core.ui

/**
 * The iOS app's words for the stream screen, the drawer and the connect screen, so every platform
 * says the same thing in the same place. clients/design/check_copy.py finds each literal here in the
 * iOS sources (interpolations as wildcards) and fails when one is no longer there.
 */
object Copy {
    // The bar (TopBar, PortraitStreamScreen).
    const val apps = "Apps"
    const val keyboard = "Keyboard"
    const val desktop = "Desktop"
    const val settings = "Settings"
    const val menus = "Menus"
    const val openAppList = "Open the app list"
    const val closeAppList = "Close the app list"
    const val showKeyboard = "Show the keyboard"
    const val hideKeyboard = "Hide the keyboard"
    const val showDesktop = "Show the host’s whole desktop"
    const val closeSettings = "Close settings"
    fun settingsFor(mac: String) = "Settings for ${mac.ifEmpty { "the host" }}"
    const val textSize = "Text size"
    fun textSizeValue(scale: Double?) = "${TextScale.label(scale ?: 1.0)} times"

    // The trackpad (Trackpad in TrackpadView.swift).
    const val trackpadHint = "Drag to move the pointer. Tap to click, two fingers to scroll."

    // The thumbnails and their lights (WindowStrip, WindowLightsMenu).
    fun thumbnail(app: String, title: String, active: Boolean) = "$app window: $title" + if (active) ", showing now" else ""
    const val close = "Close"
    const val minimize = "Minimize"
    const val fullScreen = "Full Screen"
    fun windowActions(app: String) = "$app window actions"

    // The drawer (AppDrawer).
    fun searchApps(mac: String) = "Search apps on $mac"
    const val openNow = "Open now"
    const val allApps = "All apps"
    fun windows(count: Int) = if (count == 1) "1 window" else "$count windows"

    // The connect screen (ConnectScreen).
    const val connectTitle = "Connect to a Host"
    const val addMacTitle = "Add a Host"
    const val addMac = "Add a Host…"
    const val searchNearby = "Search Nearby"
    const val alsoLookingNearby = "Also looking nearby"
    fun nearbyHint(device: String) = "Your host has to be on the same Wi‑Fi network as this $device, or have Direct Wireless Connection turned on in Sill. Away from home, add it once with a code from your host."
    const val needsMacApp = "Needs the free Sill app on your computer."
    fun getItAt(site: String) = "Get it at $site"
    const val support = "Support"
    const val privacyPolicy = "Privacy Policy"
    const val updateInAppStore = "Update Sill in the App Store"

    // The Add a Mac card (AddMacCard).
    const val addMacPairOnce = "Pair once, and Sill reaches your host from anywhere, through your VPN or the internet."
    const val addMacTyped = "Type the address and code that Sill shows on your host."
    const val addMacTypedShort = "Type the address and code from your host."
    const val enterCodeInstead = "Enter Code Instead"
    const val pair = "Pair"
    const val cancel = "Cancel"
}

/**
 * Words the iOS app has no counterpart for, because the platform lacks what iOS uses there: no
 * camera to scan the Mac's code on a PC, so a pasted pairing link stands in for the scan. Kept
 * apart so check_copy.py checks everything above against the iOS app and leaves these alone.
 */
object PlatformCopy {
    const val usePairingLink = "Use a Pairing Link Instead"
    const val pastePairingLink = "Paste the pairing link from your host’s Sill."
}
