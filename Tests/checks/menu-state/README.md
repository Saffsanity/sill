# `menu-state`

**Checks:** the device's view of the Mac's menus (docs/menu-bar-plan.md §7.2): the top level, fetches joined, answered, refused, timed out, a new tree and a move's hand-over, choices and their refusals, stale menus, a bar menu built from an older top level keeping its id only while the menu there has its title (another session's versions included), every fetch carrying the title it was shown under, the rows and sections (a note a section of its own); then 5,000 random sessions in which every opened menu's completion is settled exactly once

**Compiles:** `iOSClient/MacMenuState.swift` with `Sources/StreamProtocol` (`build.sh`)
