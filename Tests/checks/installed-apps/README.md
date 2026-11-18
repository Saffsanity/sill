# `installed-apps`

**Checks:** where the Apps list finds the Mac's apps (#76): a fake applications folder in a temporary directory, with apps directly in it, in a suite's folder and two folders down (#135's depth), a helper inside a bundle, a package of another kind, a framework (a bundle that is no package), dot names at any depth, a link to a folder (not followed, a link back up included) and a folder given that is itself a link (followed, as ~/Applications can be), Safari's hidden-flagged link, bundles with one ID (the shallower wins, and at one depth the one in the folder first by name), several folders and a missing one, the sort and the name

**Compiles:** `Sources/SillHost/InstalledApps.swift`
