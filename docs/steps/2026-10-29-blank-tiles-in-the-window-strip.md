**Blank tiles in the window strip (2026-10-29, addhumal's PR #223 with maintainer edits; issue #114).** The reporter
(a Mac Studio, macOS 27.0.1, an iPad Pro) saw a tile with macOS's generic app icon and a blank white picture for each
window or app, which nothing could bring forward. Not reproduced: this Mac (27.0.1, Stage Manager off) lists only
apps' titled windows. A read-only probe of ScreenCaptureKit's list (as the catalog reads it) found: the device shows
the generic icon only for an owner whose app has none of its own (WindowManager, SystemUIServer, Notification Center,
the screenshot tools) and two letters for an owner with no bundle; macOS 27 lists the window server's windows under an
owner with no name, which the catalog left out already; a tool with no bundle is listed under its executable's name
with an empty bundle identifier. `CatalogWindows` (pure, `Tests/checks/catalog-windows`, 75 checks, 29 mutants) holds
the catalog's whole filter: an app's window as before (an owner with a name, layer 0, over 100 × 100 points, not
Sill's), and no helper's: LayerProbeParent (as before), macOS's own interface whatever the title
(com.apple.WindowManager: Stage Manager's strip, the wallpaper from macOS 27; the Dock, Control Center,
SystemUIServer, Notification Center, the screenshot tools: the owners ScreenCaptureKit recorders leave out of their
pickers), and an untitled window of a process with no bundle (the PR's own rule). Not kept from the PR: its
WindowServer clause (dead: no name) and its AppKit XPC clause (an untitled window of the open and save panel service,
which owns apps' Open and Save panels, Chrome's and Keychain Access's among them on macOS 27.0.1: someone's work); the rule left InstalledApps (#231 edits the same files).
Sill.log names each owner left out, once ("Catalog: leaving out the windows of WindowManager
(com.apple.WindowManager): they are macOS's own, not an app's."). Verified: the check and its mutants, `run-all.sh`
all 57, `swift build -c release` (only the CaptureProbe warning), H2 against main (idle identical masked and sorted;
with a client identical but for the seconds where it comes and goes, which differ run to run on either build); this
Mac's live list judged by main's filter, the PR's and this one (the same six windows and no line; a probe's invisible
test window of a tool with no bundle left out, with its line). Untested, for Noah and the reporter: Stage Manager on
(no strip tiles, the WindowManager line), a border tool (JankyBorders), an app's Save panel in regular mode
(still a tile).
