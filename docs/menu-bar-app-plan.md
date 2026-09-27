# Sill menu bar app — plan

Written 2026-09-23 by the Opus/max design workflow (2 readers, 3 designers, 1 judge). Implementation, review and fix were deliberately stopped here; resume from this plan.

## Judge's decision

- Design 0 — **Menu bar Sill.app from a hand-written macApp/Sill.xcodeproj over a new SillHostKit library (designer 2: Xcode app target)**: 8/10. Winner. Signed .app in one command: 9. Scripts/make-app.sh ran end to end: it signed with Noah's Apple Development identity headless, the designated requirement still matched after a rebuild, and the actool-compiled icon renders natively on macOS 27 where the sips/iconutil .icns got the grey tile. '--install --open' is the one command. CLI unchanged: 9. The sorted, digit-masked output diff against the baseline was empty, exit codes stayed 130/143, and every flag still works. Reproducibility: 9. One build system: swift build compiles the CLI, the core and the app; an incremental build takes about 2 s. Polish: 6. MenuBarExtra(.menu) shows status as greyed rows. The Settings scene opens from AppKit only through an openSettings action captured from the label view, and its windows opened visible but not key. The Log is a SwiftUI Window scene, which may auto-open at launch on macOS 14. There is no App Nap guard, and the log mirror is the unified log, not a file you can tail. Risk: 8. Only main.swift moves, and all core edits were prototyped against the current tree. Gaps: turning the virtual display off reuses the stale SCWindow from the virtual display (no catalog refresh). A virtual-display toggle restarts even a Desktop stream. The prototype's StreamServer lost the advertise comment.
- Design 1 — **Sill.app menu bar host: runtime model, menu and Settings UX, HostSettings, Quit (designer 3)**: 6/10. Signed .app in one command: 7. Xcode automatic signing matches how Noah already works, and Organizer would help at M6. But only an ad-hoc build under a throwaway bundle ID was ever run. The appiconset made with sips gets macOS 26+'s grey-tile treatment. A DerivedData build makes a poor login item, and 'one command' means Cmd-R plus copying the app by hand. CLI unchanged: 9. With onFailed nil the CLI still exits(1), and 60 fps was verified. Reproducibility: 5. Two build systems compile the host, and swift build never compiles the app, so a core API change breaks it unnoticed. The hand-written objectVersion-77 pbxproj needs Xcode 16+, and Debug builds run the host at -Onone. Polish: 6. MenuBarExtra plus the Settings scene have the same activation and opening limits as Design 0, and the status icon is an SF Symbol. Its AppKit Log window, the log file and defaults KVO are good. Risk: 5. It moves 16 files while other sessions edit them and retargets the probe's symlink. Its re-resolve of the window after the virtual display is turned off, and the listener that still exits by default, are grafted into the plan.
- Design 2 — **Sill.app menu-bar host, built with SwiftPM only: a host library, two executables and a script that wraps and signs the bundle**: 7/10. Signed .app in one command: 6. It names the right needs (Apple Development signing, the icon in the bundle, one install path) but has no script, icon pipeline or proof that signing works. CLI unchanged: 8. A convenience init and the default exit(1) keep the CLI as it is, and the knob values move to HostConfig.standard, but none of it was prototyped on the real tree. Reproducibility: 7. It assumes SwiftPM with package access (verified in a probe), and its debug hooks make the app testable headless, but it also moves 16 files. Polish: 9, the best of the three. Its menu is an AppKit status item with open/close hooks and a live status card, plus a full copy deck, subtitles, attention items and onboarding. Its Settings window is AppKit-owned with SwiftUI panes: it opens from reopen and onboarding and stays off the virtual display. It adds a hidden main menu for Cmd-C/Cmd-F and a Quit that handles full-screen windows. It verified two real traps: App Nap for a windowless app, and nested modal loops starving the main queue. Risk: 6. Many new moving parts: status pulled as snapshots via queue.sync, an untested rebuild-and-retry of the listener, terminateLater, and prompt gating. Its rule to disable the login toggle on SMAppService .notFound is wrong: Design 0 measured .notFound for an app that was never registered.

**Winner: design 0** — Menu bar Sill.app from a hand-written macApp/Sill.xcodeproj over a new SillHostKit library (designer 2: Xcode app target)

## Final plan

FINAL PLAN: Sill.app, a menu bar host built with SwiftPM and one script

The base is Design 0: SwiftPM only, the host becomes a library by moving one file, and Scripts/make-app.sh wraps and signs the bundle.

From Design 2:
- The AppKit app shell: NSStatusItem + NSMenu with delegate hooks, and AppKit-owned Settings and Log windows that host SwiftUI.
- The HostConfig value type, committed inside select, with its restart rules.
- `package` access instead of public.
- The App Nap guard and the rule against nested modal loops.
- Permission-prompt gating and onboarding.
- A Quit that handles full-screen windows.
- The status copy, the hidden main menu and the debug hooks.

From Design 1:
- The log file.
- A listener that still exits by default; only the app opts out.
- Reading the window again after leaving the virtual display.

WHY SWIFTPM (a) OVER AN XCODE PROJECT (b)
- One build system. `swift build -c release` compiles the CLI, the core and the app, so a core API change cannot silently break the app, and it is the command every session already runs.
- The script was run end to end. It signed with 'Apple Development: … (HG877AGTQ7)' (team 9B2KKVM937) with no keychain prompt. The designated requirement still matched after a rebuild. The actool icon renders natively on macOS 27; the sips .icns got a grey tile.
- (b) is the move at M5 if CloudKit needs a provisioning profile. The library split keeps that cheap: flip `package` to `public`.

WHY APPKIT AND NOT MenuBarExtra + THE SwiftUI Settings SCENE
- Since macOS 14 the Settings scene opens only from inside SwiftUI views; `showSettingsWindow:` no longer works. So the reopen handler and first-launch onboarding could not open it.
- Its window cannot be kept off the Sill virtual display.
- MenuBarExtra has no open/close hooks.
- A SwiftUI Window scene may auto-open at launch on macOS 14.
- The Settings window looks the same either way: toolbar tabs and grouped SwiftUI Forms.

HARD RULES
- Never commit, stash, checkout or switch branch. Never edit docs/BRIEF.md.
- Keep the uncommitted hunks in CLAUDE.md, StreamCoordinator.swift and StreamServer.swift. That includes `advertise: !synthetic` and its 3-line comment, which Design 0's prototype StreamServer lost.
- Re-apply the edits yourself; never copy prototype files over repo files. Re-read each file right before editing it.
- Never use SCStream.updateConfiguration.
- Never call MainActor.assumeIsolated in core code. Under the CLI's dispatchMain() the main queue drains on a worker thread and the call traps; Designs 0 and 1 both reproduced this. Core code hops with `Task { @MainActor }`.
- Claude never runs `make-app.sh --install` or `--open`, tccutil, or anything that changes System Settings. Those are Noah's steps.

STEP 0: AFTER THE REBOOT
- /private/tmp is cleared at boot on this Mac (nothing in it is older than the last boot), so the scratchpad prototypes and sillclient.py are probably gone.
- Copies are in /Users/noah/Downloads/winstream/.build/menu-bar-design-refs/ (gitignored). They are reference only:
  - sillclient.py
  - d0/: Package.swift, Scripts/make-app.sh, Packaging/, the core edits, the CLI main, the app shell, edit_core.py, glyph/, iconcheck/render.swift
  - d1/: LogWindow, Permissions, LoginItem, SettingsStore
  - d2/: glyph.swift, pane-light.png and pane-dark.png, the d3*.swift threading and quit experiments, the d3probe sources
- Use `python3 .build/menu-bar-design-refs/sillclient.py PORT 5 desktop` for the synthetic check. Never `rm -rf .build`.
- Baseline, with $S as the session scratchpad:
  1. `swift build -c release`
  2. `.build/release/SillHost --synthetic > $S/base.log 2>&1 &`
  3. `lsof -nP -iTCP -sTCP:LISTEN -a -p PID`
  4. sillclient for 5 s; expect ≥50 fps.
  5. `kill -TERM PID`
- Defaults Noah can override before the first grant. TCC, Login Items, the defaults domain and M5 iCloud all key off the bundle ID:
  - CFBundleIdentifier me.saffer.sill.mac, name Sill.
  - Installed at /Applications/Sill.app.
  - Virtual display off by default in both the CLI and the app.

STEP 1: Package.swift (one file moves)
- `git mv Sources/SillHost/main.swift Sources/SillHostCLI/main.swift`
- Targets:
  - `.target(name: "StreamProtocol")`
  - `.target(name: "SillHostCore", dependencies: ["StreamProtocol"], path: "Sources/SillHost")`. Comment why: the folder name stays so doc paths and the VirtualDisplayProbe symlink stay valid.
  - `.executableTarget(name: "SillHostCLI", dependencies: ["SillHostCore", "StreamProtocol"])`
  - `.executableTarget(name: "SillMenuBar", dependencies: ["SillHostCore", "StreamProtocol"])`
  - CaptureProbe and VirtualDisplayProbe unchanged.
- Products:
  - the StreamProtocol library
  - `.executable(name: "SillHost", targets: ["SillHostCLI"])`, so `swift run -c release SillHost …` and .build/release/SillHost are unchanged
  - `.executable(name: "SillMenuBar", targets: ["SillMenuBar"])`
  - No product for SillHostCore, so the iOS project never sees it.
- Keep tools 5.9 and Swift 5 language mode.
- Access is `package`. It was verified with tools 5.9, including `package internal(set)` on an @Observable class. Mark `package` only:
  - StreamCoordinator: the class, init, start, apply, retryVirtualDisplay, keepRunningOnListenerFailure, status, config, active, windowCount, stagedWindowIsFullScreen, beginLeavingFullScreenForQuit, shutdownForExit, and a static isSillVirtualDisplay(_ id: CGDirectDisplayID) that compares CGDisplayVendorNumber with VirtualStage.vendorID.
  - Stats: the class, shared, startPrinting.
  - HostShutdown: the enum, install, releaseForQuit.
  - EncoderSelfTest.run and VirtualDisplaySelfTest.run.
  - The new HostConfig, HostStatus and HostLog types.

STEP 2: Sources/SillHost/HostConfig.swift (new)
- `package struct HostConfig: Equatable, Sendable`, with fields:
  - maxFPS: Int
  - captureScale: CGFloat
  - bitrate: Int (bits per second per 60 fps)
  - prioritizeSpeed: Bool
  - virtualDisplay: Bool
- Carry over the knob comments from main.swift:10-14.
- `package static let standard = HostConfig(maxFPS: 120, captureScale: 2, bitrate: 15_000_000, prioritizeSpeed: false, virtualDisplay: false)`. It holds both the CLI's knobs and the app's defaults, in one place ("change, rebuild, measure").
- `validated()`:
  - maxFPS clamped to 24…120
  - captureScale 2 if ≥1.5, else 1
  - bitrate clamped to 1–100 Mbps
- `changes(to:) -> String`, for the log line. Example: 'frame rate limit 120 → 60 fps, bitrate 15 → 8 Mbps per 60 fps, Retina → points, speed off → on, virtual display off → on'.

STEP 3: StreamCoordinator.swift (line numbers from the current tree)
(a) Replace the knob `let`s:
- Remove maxFPS (:14), scale, bitrate and prioritizeSpeed (:28-30), and virtualDisplay (:42).
- Add `package private(set) var config: HostConfig`, plus computed maxFPS, scale (config.captureScale), bitrate, prioritizeSpeed and virtualDisplay. The reads at :22, :27, :501 and :731 and the ~20 virtualDisplay branches keep their text.
- Add `private var pendingConfig: HostConfig?`, `private let appKitLoop: Bool`, `private var apiChecked = false` and `private var apiProblem: String?`.

(b) New init, replacing :91:
- `package init(config: HostConfig, synthetic: Bool = false, appKitLoop: Bool) throws`
- `self.config = config.validated()`, with virtualDisplay forced off when !appKitLoop.
- Assign `self.status = HostStatus()` in the init body (not as a default argument or property initializer).
- Everything else as today, including `StreamServer(advertise: !synthetic)`.

(c) Move :177-187 into `private func enableVirtualDisplay()`:
- The first call runs `VirtualDisplay.checkPrivateAPI()` and prints today's two lines verbatim.
- Every call sets `stageLosses = 0; stage.disabledReason = apiProblem; status.snapshot.virtualDisplayProblem = apiProblem`.
- start() calls it at the same spot under `if virtualDisplay`, so the CLI's output order is unchanged.

(d) `start(preselect: String?, promptForPermissions: Bool = true)`. The CLI's path is unchanged. With false (the app):
- Skip `InputInjector.ensureAccessibility()`, so no system alert appears at launch.
- Run the initial `await catalog.refreshWindows()` (:190) only when `CGPreflightScreenCaptureAccess()` is true. The first SCShareableContent call raises the Screen Recording alert; it should come from a click in Settings or a device connecting.

(e) Apply settings live:
```
package func apply(_ requested: HostConfig) async {
  guard !shuttingDown else { return }
  var new = requested.validated(); if !appKitLoop { new.virtualDisplay = false }
  guard new != (pendingConfig ?? config) else { return }
  pendingConfig = new
  await applyPending()
}
private func applyPending() async {
  guard let new = pendingConfig, !switching, !shuttingDown else { return }   // select's defer calls it again
  guard restartNeeded(for: new) else { adopt(new); pendingConfig = nil; return }
  let leavingStage = config.virtualDisplay && !new.virtualDisplay && stage.isStaged
  await select(active, bringForward: leavingStage)   // committed inside select
}
```
- `restartNeeded(for:)` is false when active == .none. Otherwise it is true when any of these holds:
  - The effective rate under new.maxFPS differs from `fps`. The effective rate is min(new.maxFPS, max(24, the highest client rate)), capped at 60 on the software encoder.
  - The effective capture scale differs; on the software encoder it is min(scale, 1).
  - bitrate or prioritizeSpeed differ.
  - virtualDisplay differs and active is .window. The Desktop never uses the display, so it never restarts for this.
- In select, between `server.resetForNewStream()` (:385) and `fps = effectiveFPS` (:386):
```
if let next = pendingConfig {
  pendingConfig = nil
  if config.virtualDisplay && !next.virtualDisplay {
    // The virtual display block below is skipped once the flag reads off: send the window home now,
    // and re-read the catalog so the .window lookup below gets its home frame, not the staged one.
    await stage.leaveFullScreenIfNeeded(); stage.release()
    if case .window = source { await catalog.refreshWindows() }
  }
  adopt(next)
}
```
- `adopt(_:)`:
  1. Set `config = next` and `catalog.preferMainDisplay = next.virtualDisplay`.
  2. If the mode turned off, call `stage.release()`; it is idempotent.
  3. If the mode turned on, call `enableVirtualDisplay()`.
  4. `print("Settings: " + old.changes(to: next))`
- In select's defer (:361-377), after the viewport tail: `if pendingConfig != nil { Task { @MainActor in await self.applyPending() } }`.
- The CLI never calls apply, so none of this runs there.
- Raising the window when the virtual display is turned off (bringForward) is a product call for Noah.

(f) `package func retryVirtualDisplay() async`, for the Try Again button: `enableVirtualDisplay()`, then `if virtualDisplay, case .window = active { await select(active) }`.

(g) At :605 and :630, `activePID(trustAppKit:)` gets `appKitLoop`. The CLI passes its --virtual-display flag, so nothing changes there. The app passes true: a behaviour change in regular mode, for Noah to test.

(h) Status writes, all on the main actor. Server callbacks hop with `Task { @MainActor }`.
- :100-120: add or remove devices.
- :173 and :759: softwareEncoder.
- :433-437: lastStageFailure, cleared on a successful stage.
- :526: status.snapshot.stream. Add `title:` and `kind:` parameters to startPipeline: 'App — Window', 'Whole Desktop' or 'Test Pattern'.
- active's didSet (:66): .none clears the stream.
- stageLost (:741): virtualDisplayProblem.
- `Stats.shared.onTick`: encodedFPS = counts['enc.out'] ?? 0, via `Task { @MainActor }`.
- Listener state, registered name and port. Clients get their names from ClientStats.

(i) New `package` members:
- `windowCount { catalog.infos.count }`
- `stagedWindowIsFullScreen`: placement exists and `WindowSizer.isFullScreen(p.element)`.
- `beginLeavingFullScreenForQuit()`: `_ = WindowSizer.perform(.fullScreen, element: p.element)`.
- `keepRunningOnListenerFailure()`: sets server.onListenerFailed so a failure is recorded in status instead of exiting.
- shutdownForExit becomes `package`.

STEP 4: Sources/SillHost/HostLog.swift (new)
- `package final class HostLog: @unchecked Sendable` with `static let shared`. State is guarded by an NSLock.
- `configure(keepLines:fileURL:)` is called once before the host starts. The defaults are keep 0 and no file, so the CLI pays one lock and a bool check per line and its stdout stays byte-identical.
- The ring holds `Line { seq: UInt64, date: Date, text: String }`, capacity 5,000, read with `lines(after:)`.
- `onAppend` fires on the main queue, coalesced to at most one call per 100 ms, and only while it is set.
- The file sink:
  - Path: ~/Library/Logs/Sill/Sill.log by default; `-SillLogFile` overrides it.
  - Writes go through a serial .utility DispatchQueue with one cached DateFormatter ('yyyy-MM-dd HH:mm:ss.SSS '), never on the capture, VideoToolbox or network threads.
  - Rotates to Sill.1.log at launch and whenever it passes 10 MB.
  - `fileURL` is exposed.
- `line(_:)` echoes and records a line, for the app's own code.
- The module-level shadow:
  ```
  func print(_ items: Any..., separator: String = " ", terminator: String = "\n") {
      let t = items.map { String(describing: $0) }.joined(separator: separator)
      Swift.print(t, terminator: terminator)
      HostLog.shared.append(t)
  }
  ```
- Document at its definition that it is implicit, that Swift.print bypasses it, and that it covers SillHostCore only.
- None of the 94 call sites uses `to:` or `terminator:` (checked), so they all stay untouched.

STEP 5: Sources/SillHost/HostStatus.swift (new; status is pushed, nothing polls)
- `package struct HostStatusSnapshot: Equatable`. Not Sendable: Design 1 got warnings when it marked these structs Sendable.
  - network: .starting, .registering, .advertising(name), .notAdvertised(port), .waiting(String) or .failed(String)
  - devices: [Device], each with id (ObjectIdentifier), endpoint, and optional name, fps, frameAgeMs and rttMs
  - stream: Stream?, with kind, title, width, height, fps, mbps, onVirtualDisplay and softwareEncoder
  - encodedFPS, softwareEncoder, virtualDisplayProblem, lastStageFailure, synthetic
- `@MainActor @Observable package final class HostStatus { package internal(set) var snapshot = HostStatusSnapshot() }`

StreamServer.swift:
- `var onListenerFailed: ((NWError) -> Void)?`. At :101-103 keep printing 'Listener failed: …', then call it if set, else `exit(1)` as today. Set it only before start().
- `var onListenerState`.
- `listener.serviceRegistrationUpdateHandler`: on `.add(.service(name, _, _, _))`, call `onServiceRegistered(name)`. That is the name Bonjour actually registered, including '(2)' after a rename.
- `var port: UInt16? { listener.port?.rawValue }`
- At :180, decode every ClientStats report, keep the 1.5 s print gate, and call `onClientStats(connection, stats)`.

Stats.swift:
- `var onTick: (([String: Int]) -> Void)?`, called in tick() after unlock and before the print.

STEP 6: Other core edits
- HostShutdown.swift:
  - Make it `package`, and say in the doc comment that the app always installs it.
  - New `@MainActor package static func releaseForQuit(coordinator:)`: the same `began` guard and 'Shutting down: …' line, a 3 s watchdog on a global queue that calls exit(0), and `coordinator?.shutdownForExit()`. No exit; AppKit exits.
- InputInjector.launchingAppName() (:449): when getppid() == 1 and Bundle.main has CFBundleDisplayName, return that name ('Sill'). That is a LaunchServices launch, where today it would say launchd. Keep the Terminal wording otherwise.
- EncoderSelfTest.run and VirtualDisplaySelfTest.run become `package`.

STEP 7: Sources/SillHostCLI/main.swift
- Add `import SillHostCore`.
- Replace :10-14 with `var config = HostConfig.standard` and a comment that the knobs now live in HostConfig.swift.
- After the flags: `config.virtualDisplay = virtualDisplay`.
- :57 becomes `let c = try StreamCoordinator(config: config, synthetic: synthetic, appKitLoop: virtualDisplay)`.
- :63 uses `c.windowCount`.
- Everything else stays byte-identical: flags, self-tests, preselect, CGMainDisplayID, the .prohibited NSApplication branch with HostShutdown, dispatchMain, and the Terminal hint with exit(1).

STEP 8: Gate
Run tests T1-T3 below and get them green before any app work.

STEP 9: Packaging (tested reference in d0/)

Packaging/Info.plist:
- CFBundleIdentifier me.saffer.sill.mac
- CFBundleName and CFBundleDisplayName Sill
- CFBundleExecutable Sill; CFBundlePackageType APPL
- CFBundleShortVersionString 0.3.0; CFBundleVersion is set by the script from `git rev-list --count HEAD`
- CFBundleIconFile and CFBundleIconName AppIcon
- CFBundleInfoDictionaryVersion 6.0; CFBundleDevelopmentRegion en
- LSMinimumSystemVersion 14.0
- LSUIElement true
- LSApplicationCategoryType public.app-category.utilities
- NSPrincipalClass NSApplication
- NSSupportsAutomaticTermination false; NSSupportsSuddenTermination false
- NSLocalNetworkUsageDescription 'Sill makes this Mac visible to your iPhone and iPad on the same network so they can stream its windows.'
- NSBonjourServices [_sill._tcp]
- NSHumanReadableCopyright

Packaging/SillDebug.entitlements:
- Only com.apple.security.get-task-allow.
- No sandbox and no other entitlements: CGVirtualDisplay is looked up at runtime.

Scripts/make-app.sh (start from d0/Scripts/make-app.sh):
1. `swift build -c release --product SillMenuBar`; take the bin path from `--show-bin-path`.
2. Assemble .build/Sill.app.partial: the binary becomes Contents/MacOS/Sill, plus Info.plist and PkgInfo.
3. Icon:
   - `qlmanage -t -s 1024` renders design/AppIcon.svg.
   - The render becomes the one layer of a generated Icon Composer document.
   - Compile with `xcrun actool --compile <abs>/compiled --platform macosx --minimum-deployment-target 14.0 --app-icon AppIcon --output-partial-info-plist <abs>/partial.plist <abs>/AppIcon.icon`. Absolute paths only.
   - Cache the output in .build/icon. Packaging/AppIcon.icon wins when it exists.
4. Sign last, run `codesign --verify --strict`, move the bundle over .build/Sill.app, and print the identity and the designated requirement.

Signing:
- Identity: `$SILL_SIGN_IDENTITY`, else the first 'Apple Development:' identity from `security find-identity -v -p codesigning`, else ad hoc with a loud warning.
- Dev builds: `codesign --force --options runtime --timestamp=none --entitlements Packaging/SillDebug.entitlements --sign "$identity" .build/Sill.app.partial`
- `--release`: `codesign --force --options runtime --timestamp --sign "$identity" …`

`--install`:
1. `pkill -TERM -f 'Sill\.app/Contents/MacOS/Sill'`. HostShutdown then puts windows back. Never use `pkill -x Sill`: it would match the Simulator's Sill.
2. Wait up to 5 s.
3. New guard: refuse to replace ${SILL_INSTALL_DIR:-/Applications}/Sill.app unless its CFBundleIdentifier is me.saffer.sill.mac. An iPad build of the iOS client installed on the Mac would also live at /Applications/Sill.app.
4. `rm -rf` the old copy, then `ditto` the new one.
5. Run `lsregister -u` on .build/Sill.app so LaunchServices knows one Sill.

`--open` opens the installed copy.

NOAH'S COMMAND: `cd ~/Downloads/winstream && Scripts/make-app.sh --install --open`

STEP 10: App target Sources/SillMenuBar/ (AppKit lifecycle, like the CLI's --virtual-display branch)

main.swift, in order:
1. `setvbuf(stdout, nil, _IOLBF, 0)`; `signal(SIGPIPE, SIG_IGN)`
2. `HostLog.shared.configure(keepLines: 5000, fileURL: <-SillLogFile or ~/Library/Logs/Sill/Sill.log>)`
3. `--encoder-selftest` runs EncoderSelfTest.run().
4. `_ = CGMainDisplayID()`
5. `--virtual-display-selftest` runs VirtualDisplaySelfTest.run().
6. `let app = NSApplication.shared; app.setActivationPolicy(.accessory)`. The bare binary has no LSUIElement.
7. Keep the delegate in a global, `let delegate = MainActor.assumeIsolated { AppDelegate() }`. NSApplication.delegate is weak.
8. `app.delegate = delegate`; `app.mainMenu = MainMenu.make()`; `app.run()`

AppLog.swift: a 3-line print shadow that forwards to HostLog.shared.line.

AppDelegate.swift (@MainActor):
- applicationDidFinishLaunching, in order:
  1. `DebugHooks.renderPreviewsIfAsked()` (exits when asked).
  2. `disableAutomaticTermination('Sill serves devices from the menu bar')` and `disableSuddenTermination()`.
  3. `StatusItemController.install()`, showing 'Starting…'.
  4. `HostShutdown.install { model.coordinator }`. Always: the virtual display can be switched on at runtime.
  5. `model.start()`
  6. `DebugHooks.schedule(model:)`
- applicationShouldHandleReopen shows Settings.
- Quit is covered in step 14.

AppModel.swift (@MainActor @Observable):
- Owns settings (HostSettings.load()), coordinator, startupError, permissions (PermissionsModel), loginItem (LoginItemModel) and synthetic (`CommandLine.arguments.contains("--synthetic")`).
- start(), inside a `Task { @MainActor }`:
  1. `c = try StreamCoordinator(config: settings.config, synthetic: synthetic, appKitLoop: true)`; `c.keepRunningOnListenerFailure()`
  2. `settings.onChange = { Task { @MainActor in await c.apply(self.settings.config) } }`. Reading the latest value when the task runs means out-of-order tasks still converge.
  3. `observePresentation()`
  4. `await c.start(preselect: nil, promptForPermissions: false)`
  5. `Stats.shared.startPrinting()`
  6. Log a line with the version, build, bundle path and log path.
  7. `onboardIfNeeded()`
  - On an error, set startupError and log it. Never exit.
- `observePresentation()` is a withObservationTracking loop that re-arms after each change and hops with a Task on each one:
  - Recompute `StatusText.present(…)` and update the glyph, tooltip and accessibility label.
  - Log 'Status: <header> — <subtitle>' whenever the header changes; tests grep for it.
  - Update the App Nap activity.
- App Nap: while at least one device is connected, hold `ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical], reason: "Sill is serving a connected device")`; end it at zero devices. A windowless accessory app can be napped (the CLI never was). Coalesced timers would starve the 30 ms keepalive ticks and bring back the stutter. Keeping the Mac awake while streaming (.userInitiated) is a product call for Noah.
- `onboardIfNeeded()`: when not synthetic, a permission is missing and permissionsOnboardingDismissed is false, open Settings on the Permissions tab.

HostSettings.swift (app only, @MainActor @Observable):
- `var config: HostConfig { didSet { guard config != oldValue …; save(); onChange?() } }`
- UserDefaults keys: maxFPS (Int), captureScale (Double), bitrate (Int), prioritizeSpeed, virtualDisplay.
- `register(defaults:)` from HostConfig.standard; load through validated(). Argument-domain overrides such as `-maxFPS 60` then work for one run.
- UI keys: settingsTab, permissionsOnboardingDismissed, askedScreenRecording, askedAccessibility, logShowsStats.
- Launch at login is not stored here; SMAppService is the source of truth.
- `QualityPreset`: efficient 8M, balanced 15M, high 25M, maximum 40M, titled like 'Balanced — 15 Mbps'. Any other stored bitrate shows as 'Custom — N Mbps'.
- No sliders: one change is one apply and at most one restart.

MainMenu.swift. Accessory apps show no menu bar, but key equivalents still route through the main menu:
- Sill: About Sill (orderFrontStandardAboutPanel), Settings… ⌘,, Quit Sill ⌘Q.
- Edit: Undo/Redo, Cut/Copy/Paste, Select All, and Find ▸ Find… ⌘F / Find Next ⌘G / Find Previous ⇧⌘G, all via `performFindPanelAction:` with tags 1, 2 and 3.
- Window: Minimize ⌘M, Close ⌘W.

STEP 11: Status item and menu

StatusGlyph.swift:
- Port d2/glyph.swift: AppIcon.svg's geometry, the iMac outline with the tilted iPad.
- States: idle, connected, streaming, attention.
- `NSImage(size:flipped:drawingHandler:)`, 18 pt, `isTemplate = true`.
- Fallback: SF Symbol macbook.and.ipad.

StatusText.swift: a pure `present(snapshot:permissions:startupError:hasCoordinator:) -> StatusPresentation` (glyph, header, subtitle, source row, device rows, attention items, tooltip). Title case in menus, sentence case in explanations, typographic quotes.
- Header; the first match wins:
  1. 'Sill Couldn’t Start' / <error>
  2. 'Starting…'
  3. 'Not Visible on the Network' / '<error>. Quit and reopen Sill to try again.'
  4. 'Waiting for the Network' / 'Sill appears on your iPhone and iPad once this Mac is on Wi-Fi or Ethernet and Local Network access is allowed.'
  5. 'Test Pattern Mode' / 'Not advertised; test clients connect to port N.'
  6. 'Screen Recording Is Off' / 'Devices can connect but can’t see any windows.'
  7. 'Streaming to iPad' or 'Streaming to 2 Devices'
  8. 'iPad Connected' or '2 Devices Connected' / 'Pick a window on the device to start streaming.'
  9. 'Waiting for a Device' / 'Open Sill on your iPhone or iPad. This Mac appears as “<name>”.' Until the name arrives: 'Registering on the local network…'
- Source row:
  - Title: 'Safari — Apple Developer' (middle-truncated to 44 characters), 'Whole Desktop' or 'Test Pattern'.
  - Detail: '3024×1898 · 118 of 120 fps · 30 Mbps', or '120 fps, nothing changing' when encodedFPS is 0.
  - Suffix, when it applies: ' · virtual display', ' · software encoder' or ' · real window (virtual display: <reason>)'.
- Device row: 'iPad (iPad14,1)' (the endpoint until the first report) / '118 fps · frame age 9 ms · RTT 7 ms'.
- Attention items: 'Allow Screen Recording…', 'Allow Accessibility…', and 'Hardware Encoder Not Responding' (disabled).

StatusCard.swift:
- A SwiftUI view of the presentation, 300 pt wide, shown in an NSMenuItem.view through NSHostingView.
- It re-renders while the menu is open (verified by Design 2).

StatusItemController.swift (NSObject, NSMenuDelegate):
- `NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)`, autosaveName 'SillStatusItem'.
- `menu.delegate = self`; `autoenablesItems = false`.
- Items:
  - the status card
  - attention items, only when needed, each with a non-template orange exclamationmark.triangle.fill
  - separator
  - 'Virtual Display' (checkmark)
  - 'Frame Rate' ▸ 'Up to 60 fps' / 'Up to 120 fps'
  - 'Quality' ▸ the presets
  - 'Resolution' ▸ 'Retina' / 'Standard'
  - separator
  - 'Launch at Login' (checkmark; disabled outside a bundle)
  - 'Permissions' ▸ 'Screen Recording: Allowed | Not Allowed…', 'Accessibility: …', separator, 'Open Privacy & Security…'
  - separator
  - 'Show Log…'
  - 'Settings…' ⌘,
  - separator
  - 'Quit Sill' ⌘Q, calling `NSApp.terminate(nil)`
- Subtitles: `if #available(macOS 14.4, *) { item.subtitle = … }`, with toolTip as the fallback.
- menuWillOpen: refresh permissions and the login item, set checkmarks from settings.config, and size the card to its fittingSize.
- Actions only set `model.settings.config.x`: one path to the coordinator.
- Build the items with a `MenuBuilder` that takes a presentation, a config, the login state and the permissions, so the previews hook can dump them.
- Verified by Design 2: while a menu opened by a click is tracking, main-queue timers, `DispatchQueue.main.async` and `Task { @MainActor }` hops keep running, so the host stays live.

THE MODAL-LOOP RULE (put it in AppDelegate's doc comment and in CLAUDE.md)
- Never start a nested modal loop from `Task { @MainActor }`, an async continuation or a `DispatchQueue.main` block. That covers NSMenu.popUp, NSAlert.runModal, NSApp.runModal, NSSavePanel.runModal, and NSApp.terminate when it can return .terminateLater.
- The serial main queue stops every host hop (input, client messages, selects, Stats) until the loop ends, and a terminate issued from a Task never gets its reply. Design 2 verified both.
- Start them only from AppKit target/action, SwiftUI Button actions or a run-loop Timer. Show errors inline, not in alerts.
- App code may call `MainActor.assumeIsolated` in main-queue callbacks, because the app always runs NSApplication. Core code may not.

STEP 12: Settings window, permissions, login item

SettingsWindow.swift:
- An NSWindowController with `NSWindow(contentViewController: NSTabViewController)`, tabStyle .toolbar.
- One `NSTabViewItem(viewController: NSHostingController(rootView: pane))` per tab, with `sizingOptions = [.preferredContentSize]`. Symbols: gearshape, play.rectangle, display, lock.shield.
- Style titled, closable and miniaturizable; `isReleasedWhenClosed = false`; `setFrameAutosaveName("SillSettings")`; `collectionBehavior` .moveToActiveSpace.
- `show(tab:)`:
  1. If the window has no screen or sits on the Sill virtual display (`StreamCoordinator.isSillVirtualDisplay`), center it on `NSScreen.screens.first!.visibleFrame`.
  2. `NSApp.activate()`, then `makeKeyAndOrderFront(nil)`.
  3. On the next main turn, if the window is not key, `orderFrontRegardless()`. Design 0 saw windows open visible but not key.
- `windowShouldClose` sets the onboarding-dismissed flag when a permission is still missing.

SettingsPanes.swift: SwiftUI `Form { }.formStyle(.grouped)`, 520 pt wide, `@Bindable var settings`, binding `$settings.config.maxFPS` and so on.
- General:
  - A Launch at login toggle, with 'Approve in System Settings…' on .requiresApproval. Outside a bundle it is disabled with 'Available when Sill runs from its app bundle'.
  - 'Running from <path>', with a warning outside /Applications: the login item and permissions follow this copy.
  - 'Visible on your network as “<name>”', with a link to System Settings › General › Sharing (x-apple.systempreferences:com.apple.Sharing-Settings.extension).
  - Show Log… and Reveal Log File.
  - Quit Sill. It gives a way out when the notch hides the status item.
  - A version footer.
- Streaming:
  - Frame rate limit: segmented 60 / 120.
  - Quality picker.
  - Resolution: Retina / Standard.
  - Footer: 'Each device asks for its own screen’s rate, up to this limit. Quality is per 60 fps; a 120 fps stream gets twice as much. Changes apply at once: the current stream restarts for a moment.'
  - Prioritize encoding speed toggle, with its caption.
  - A note while the software encoder carries the stream.
- Virtual Display:
  - Toggle 'Stream from a virtual display', with Design 2's explanation.
  - Status row: Available / Not available on this version of macOS: <reason> / Needs Accessibility / Off for this session: <reason>, plus a Try Again button that awaits `coordinator.retryVirtualDisplay()`.
  - Footer: 'Uses a private macOS interface (CGVirtualDisplay). If a macOS update breaks it, Sill streams the window where it is.'
- Permissions:
  - One row each for Screen Recording and Accessibility, with Design 2's explanations. Each shows green checkmark.circle.fill 'Allowed', or an orange warning plus one button.
  - A Local Network hint while the listener is waiting or has failed.
  - Footer: 'Access belongs to Sill itself. Access you gave Terminal for the SillHost command-line tool doesn’t carry over.'
  - 'Relaunch Sill' after a Screen Recording request.
  - A 1 s refresh runs in `.task` only while the pane is visible, plus a refresh on NSApplication.didBecomeActiveNotification.

Permissions.swift:
- Status: `CGPreflightScreenCaptureAccess()` and `AXIsProcessTrusted()`.
- Screen Recording, Allow…:
  1. The first time, `CGRequestScreenCaptureAccess()`; set askedScreenRecording.
  2. After that, open `x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture`.
- Accessibility, Allow…:
  1. `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)`
  2. After that, open `…?Privacy_Accessibility`.
- If a link fails, open the Privacy & Security root.
- Relaunch, from the button action:
  1. Start a `Process` running `/bin/sh -c 'while /bin/kill -0 "$1" 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open "$0"' <bundlePath> <pid>`.
  2. Call `NSApp.terminate(nil)`.

LoginItem.swift:
- `SMAppService.mainApp.status`:
  - .enabled: on.
  - .requiresApproval: on, with a hint and `SMAppService.openSystemSettingsLoginItems()`.
  - .notRegistered and .notFound: off. Design 0 measured that a never-registered app reports .notFound, so never disable the toggle on it.
- On: `try SMAppService.mainApp.register()`. Off: `try await SMAppService.mainApp.unregister()`.
- Errors show inline. Never switched on automatically. Re-read on menu open and when a pane appears.

STEP 13: Log window (LogWindow.swift, AppKit)
- 'Sill Log', 900×520, `setFrameAutosaveName("SillLog")`, placed like Settings.
- `NSTextView.scrollableTextView()`: not editable, selectable, `monospacedSystemFont(ofSize: 11, weight: .regular)`, `usesFindBar = true`, `isIncrementalSearchingEnabled = true`.
- Lines read 'HH:mm:ss.SSS  text', with the timestamp in secondaryLabelColor.
- On show: append `HostLog.shared.lines(after: clearedSeq)`, then set onAppend to append new lines in batches. Keep at most 5,000 lines. Follow the tail only when already at the bottom.
- On close: `onAppend = nil`.
- Bottom bar:
  - 'Show per-second stats' (logShowsStats) hides lines starting '[1s]', '[30s]' or 'client '.
  - 'Clear' clears the view only.
  - 'Reveal Log File' calls `NSWorkspace.shared.activateFileViewerSelecting`.

STEP 14: Quit, in applicationShouldTerminate
- Quit ⌘Q, logout and Screen Recording's Quit & Reopen all arrive here from the event loop.
- A second call returns .terminateNow.
- If `coordinator.stagedWindowIsFullScreen`:
  1. Call `beginLeavingFullScreenForQuit()`.
  2. Poll with a `Timer` on RunLoop.main in .common modes every 100 ms, for up to 2 s, until it is no longer full screen.
  3. Call `HostShutdown.releaseForQuit(coordinator:)` and `NSApp.reply(toApplicationShouldTerminate: true)`.
  4. Return .terminateLater. A 4 s watchdog on a global queue calls exit(0); the atexit emergencyRestore still runs.
- Otherwise call `releaseForQuit` and return .terminateNow.
- No confirmation dialog.
- Signals keep `HostShutdown.begin`: synchronous, exit code 128+signal. Never route them through NSApp.terminate.

STEP 15: DebugHooks.swift
These read the argument domain, like the iOS -SillLayout harness, and do nothing unless passed.
- `--synthetic`: as in the CLI.
- `-SillLogFile <path>`
- `-SillSetAfter '<s> key=value[,key=value][; <s> …]'`: fired by run-loop Timers, counted from launch; mutates settings.config exactly like a control would.
- `-SillQuitAfter <s>`: a run-loop Timer calls NSApp.terminate.
- `-SillRenderPreviews <dir>`: renders with `NSHostingView.cacheDisplay`, which needs no Screen Recording (see d2/pane-light.png), then calls exit(0). Output:
  - the four panes, light and dark
  - status cards for canned snapshots: idle, registering, connected, streaming, two devices, software encoder, permissions missing, test pattern, waiting, failed
  - the glyph states
  - menu.txt, from MenuBuilder, for each snapshot

STEP 16: Docs (docs/BRIEF.md stays untouched)
- CLAUDE.md:
  - Layout: SillHostCore at Sources/SillHost, SillHostCLI, SillMenuBar, Packaging, Scripts; HostConfig, HostStatus, HostLog.
  - Build and run: the script's flags; the app's arguments next to the iOS harness list; the log at ~/Library/Logs/Sill/Sill.log; `defaults read me.saffer.sill.mac`.
  - Current step: the menu bar app and its rules (package access, no assumeIsolated in core, the modal-loop rule, App Nap, TCC).
  - Keep the uncommitted edits.
- README, Mac host section:
  - Sill.app and its one command.
  - Permissions go to 'Sill', not Terminal.
  - Keep one copy in /Applications. Launch it from Finder, `open` or the login item; running Contents/MacOS/Sill from Terminal makes Terminal responsible.
  - If grants go stale: `tccutil reset ScreenCapture me.saffer.sill.mac`, then the same for Accessibility.
  - Knobs now live in HostConfig.swift.
  - M6: `SILL_SIGN_IDENTITY='Developer ID Application: … (9B2KKVM937)' Scripts/make-app.sh --release`, then `ditto -c -k --keepParent .build/Sill.app .build/Sill.zip`, `xcrun notarytool submit .build/Sill.zip --keychain-profile sill-notary --wait` and `xcrun stapler staple .build/Sill.app`. Noah stores the notary credentials himself.
- design/README.md: the Mac icon pipeline.
- Note these, but don't fix them here:
  - CLAUDE.md says the periodic keyframe interval is 30 s, but HEVCEncoder.swift:83 sets 4 s.
  - The CLI's synthetic mode still prints 'Advertising _sill._tcp', though it no longer advertises.

TESTS WITHOUT PERMISSIONS (Claude)
- T1, build:
  - Build clean into a scratch path so every warning shows: `swift build -c release --scratch-path $S/cleanbuild 2>&1 | grep -E 'error|warning:|Build complete'`. Expect 0 errors, and only the warning at Sources/CaptureProbe/main.swift:36.
  - Then run the normal `swift build -c release`.
- T2, CLI parity:
  - Run the baseline recipe on the new binary; expect ≥50 fps.
  - `diff <(grep -v '^\[1s\]' base.log | sed -E 's/[0-9]+/N/g' | sort) <(… new.log …)` must be empty.
  - No 'Settings:' or 'Status:' lines, and no ~/Library/Logs/Sill.
- T3, CLI flags:
  - `--synthetic --virtual-display`: `kill -INT` gives exit 130 with 'Shutting down…'; `kill -TERM` gives 143.
  - `swift run -c release SillHost --encoder-selftest` prints both sections and the stats line.
  - `--synthetic Safari` prints the same startup lines.
  - Optional: `--virtual-display-selftest` exits 0.
- T4, the bare app binary:
  - Run `.build/release/SillMenuBar --synthetic -SillLogFile $S/app-file.log > $S/app.log 2>&1 &`.
  - Take the port from the 'Status: Test Pattern Mode' line, or from lsof.
  - Run sillclient for 5 s. Expect ≥50 fps and 'Streaming a synthetic test pattern at 3024×1898, 60 fps, 15 Mbps'.
  - `kill -TERM` gives 143 with 'Shutting down…'. No Settings window opens.
- T5, live apply. Run with `-SillSetAfter '2 maxFPS=60'` and `sillclient.py PORT 8 desktop --fps=120`:
  - The stream goes from 120 fps, through 'Settings: frame rate limit 120 → 60 fps', to 60 fps.
  - bitrate=30000000 restarts the stream.
  - captureScale=1 gives 1512×948.
  - virtualDisplay=true while the Desktop streams prints the API line (17 selectors) and does not restart.
  - maxFPS=120 with a 60 fps client does not restart.
  - Several keys set in one step cause one restart.
- T6, quit and persistence:
  - `-SillQuitAfter 3` exits 0 with 'Shutting down…' and no watchdog line; the client sees EOF.
  - Run with `-SillSetAfter '1 bitrate=30000000' -SillQuitAfter 2`, then relaunch: the stream starts at 30 Mbps.
  - Then `defaults delete SillMenuBar`.
- T7, previews: run `-SillRenderPreviews $S/previews`, read the PNGs and menu.txt, and check them against the copy in step 11: no clipping at 520 pt, light and dark.
- T8, idle footprint: the bare binary with no client for 60 s shows about 0.0 % CPU in `ps -o %cpu,rss -p PID`.
- T9, bundle: `Scripts/make-app.sh`, without --install.
  - The output says signed by 'Apple Development: … (HG877AGTQ7)'.
  - `codesign --verify --strict --verbose=2 .build/Sill.app` passes.
  - `codesign -d -r- .build/Sill.app` shows the identifier and the leaf CN, not a cdhash.
  - `plutil -p` shows LSUIElement, CFBundleIconName and NSBonjourServices.
  - Resources holds Assets.car and AppIcon.icns.
  - A second run takes about 2 s.
- T10, grants survive rebuilds:
  1. `DR=$(codesign -d -r- .build/Sill.app 2>&1 | sed -n 's/^designated => //p')`
  2. Edit a comment under Sources/SillMenuBar and rebuild.
  3. `codesign --verify -R="$DR" .build/Sill.app` must pass.
  4. Revert the comment.
- T11, icon: render the NSWorkspace icon with d0/iconcheck/render.swift. Expect a native squircle like d0/iconcheck/final.png.
- T12, signed bundle smoke test:
  - Run `.build/Sill.app/Contents/MacOS/Sill --synthetic -SillLogFile $S/bundle.log`; expect ≥50 fps, then `kill -TERM`. Don't pass -SillSetAfter here: it would write Noah's real defaults domain.
  - Optional: run the bundle binary with `--virtual-display-selftest`; exit 0 proves display creation under the hardened runtime.
- T13, iOS unaffected: `xcodebuild -project iOSClient/Sill.xcodeproj -scheme Sill -destination 'generic/platform=iOS Simulator' -derivedDataPath $S/dd-ios CODE_SIGNING_ALLOWED=NO build` gives BUILD SUCCEEDED.
- T14, cleanup:
  - `git status` shows only the planned files and the rename, with the pre-existing hunks intact.
  - `pgrep -fl 'SillHost|SillMenuBar|Sill.app/Contents'` shows none of ours. The Simulator's Sill is Noah's; leave it.

TESTS FOR NOAH
- N1, first run:
  - Quit any SillHost CLI, then run `Scripts/make-app.sh --install --open`.
  - Expect a status item, no Dock icon, no ⌘Tab entry, and Settings open on Permissions.
  - Screen Recording: Allow…, then the system alert, then enable Sill in System Settings, then Quit & Reopen.
  - Accessibility turns on without a relaunch.
  - Note whether a Local Network prompt appears.
  - Both Privacy lists show Sill with its icon, and the deep links open the right panes.
- N2, menu:
  - It reads 'Waiting for a Device … “Noah’s MacBook Pro”'.
  - When the iPad connects, its row appears within about 1 s.
  - When a window is picked: 'Streaming to iPad', the source row with fps, and the glyph fills.
- N3, controls while streaming, with Show Log… open. Each change gives one 'Settings:' line and one 'Streaming …' line.
  - Quality changes the Mbps.
  - Standard resolution halves the pixel size.
  - 60/120 needs a ProMotion device to show a difference.
  - Virtual Display on: the window leaves the screen and keeps streaming.
  - Virtual Display off: the window returns to its exact frame and comes forward, and no Sill display remains.
  - Repeat with the window full screen. Clicks and typing land after each toggle.
- N4, Settings: it opens in front on the main display, even while a window is on the virtual display. The tabs mirror the menu. Values persist across relaunch (`defaults read me.saffer.sill.mac`).
- N5, rebuild: after any change, `Scripts/make-app.sh --install --open` gives no prompts, and streaming and input work at once.
- N6, Launch at Login:
  - On: Sill is listed in System Settings › General › Login Items, and it is back after logout/login.
  - Off: removed.
  - Reinstalling with --install keeps it.
- N7, quit with a staged window, via the menu, ⌘Q in Settings, pkill -TERM and logout: the window goes home, no Sill display remains, and the process is gone within 4 s.
- N8, latency and App Nap:
  - Compare -SillHUD frame age and RTT between the app and the CLI, 5 min each, including 10 min with no Mac input.
  - `pmset -g assertions | grep -i sill` shows the activity only while a device is connected.
  - Idle CPU is 0.0 % with the menu closed.
- N9, regular-mode input: with another app frontmost, tap into the streamed window from the iPad. The app activates and the first click lands. Compare with the CLI.
- N10, revocation and the notch:
  - Revoke Screen Recording while streaming: the stream stops, the glyph shows attention, and the header reads 'Screen Recording Is Off'.
  - With the status item hidden, double-clicking Sill.app opens Settings.
- N11, Log window: ⌘F, ⌘C, the stats toggle and Reveal Log File work, and `tail -f ~/Library/Logs/Sill/Sill.log` matches the window.
- N12, the CLI and the app at once: the menu shows the renamed '… (2)' or stays at 'Registering…'. Keep the virtual display on in at most one of them.

RISKS
- TCC:
  - A grant belongs to the bundle ID plus the designated requirement. Ad-hoc builds lose grants silently, and Terminal's grants don't carry over.
  - Running Contents/MacOS/Sill from Terminal makes Terminal the responsible process.
  - Two registered copies confuse LaunchServices.
  - The login item records the bundle's path.
  - Developer ID has a team-based requirement: grant once more at M6. A Developer ID certificate needs the team's Account Holder.
- Local Network privacy for a LaunchServices-launched app is untested on macOS 27. If it bites, the menu shows 'Waiting for the Network'.
- Screen Recording needs a relaunch after granting, and macOS may ask again periodically.
- Untested here, all need Noah:
  - the App Nap guard
  - toggling the virtual display with real windows
  - trusting frontmostApplication in regular mode
  - the full-screen quit path
- The print shadow is implicit and covers SillHostCore only.
- `package` must become `public` if the app ever moves to Xcode, most likely at M5 for a CloudKit provisioning profile.
- Two hosts at once share the virtual-display identity (0x5111/1/1).
- The log file holds window titles, device names and IPs; consider redaction before M6.

## The three designs, as submitted

### Design 0: Menu bar Sill.app from a hand-written macApp/Sill.xcodeproj over a new SillHostKit library (designer 2: Xcode app target)

DECISION: go with option (b). Move everything in Sources/SillHost except main.swift into a SwiftPM library target called SillHostKit. SillHost stays as a thin CLI over it. Add a hand-written project, /Users/noah/Downloads/winstream/macApp/Sill.xcodeproj. Its app target is SillMac: product Sill.app, bundle ID me.saffer.sill.mac, LSUIElement. It links the SillHostKit and StreamProtocol products through the same XCLocalSwiftPackageReference (relativePath "..") that iOSClient/Sill.xcodeproj uses.

WHY (b) OVER (a):
- Signing: Noah already signs in Xcode with team 9B2KKVM937. Automatic signing picks the only identity in the keychain, "Apple Development: … (HG877AGTQ7)". Its OU is 9B2KKVM937 and it is valid until 2027-09-22. No script has to hard-code an identity or run into keychain prompts.
- Permissions: ⌘R launches the bundle as its own responsible process, so TCC asks on behalf of "Sill". A certificate-based designated requirement keeps those grants across rebuilds. Ad-hoc signing does not: the prototype's ad-hoc build shows `designated => cdhash H"…"`.
- Icons and assets: actool compiles the asset catalog (the prototype produced AppIcon.icns and Assets.car). An Icon Composer .icon can simply be dropped into the folder.
- Previews and profiling: SwiftUI previews and Instruments (Profile action) work out of the box.
- Developer ID in M6: Organizer → Direct Distribution does signing and notarization. A script would have to reimplement all of this.
- Headless builds still work: xcodebuild builds the project without the GUI (≈14 s).
- The cost of (b) is the hand-written pbxproj. I keep it small and nearly edit-free by using the objectVersion-77 format with one PBXFileSystemSynchronizedRootGroup: new source files need no project edits.
- The split to a library (plus `public`) is needed by any separate app target. `package` access would not reach an Xcode target, because it builds with a different -package-name.

RUNTIME DESIGN:
- HostSettings (library): an @MainActor @Observable class that replaces the main.swift `let`s.
  - The coordinator copies it into a private `knobs` snapshot only inside `select`, after capture stops and before fps and staging are computed. A switch therefore never sees half a change.
  - `settingsChanged()` queues a change that arrives mid-switch (same pattern as viewportArrivedWhileSwitching). Otherwise it restarts the current source through `select`, including .none.
  - Turning the virtual display off first sends a staged window home.
- HostStatus (library, @Observable) holds:
  - the Bonjour name actually registered
  - the clients, with device name, fps and RTT from ClientStats
  - the stream description
  - the encoded fps, from a Stats.onTick hook
  - whether the virtual display is available
- HostLog: a module-level `print` in SillHostKit shadows Swift.print. It writes identical stdout (the CLI is unchanged), a 5,000-line ring buffer for the Log window, and ~/Library/Logs/Sill/Sill.log, so Noah and Claude can still `tail -f`.
- The app:
  - Scenes are a SwiftUI MenuBarExtra (.menu style, a real NSMenu) and a Settings scene. The Log window is plain AppKit (see risks).
  - The AppDelegate starts the host in applicationDidFinishLaunching, where the AppKit loop that the virtual display needs is already running. It tears down in applicationShouldTerminate via a new HostShutdown.quit.
  - Settings persist in UserDefaults and are also taken live from `defaults write` through KVO. That makes every setting scriptable and testable without clicking.
- The CLI builds a HostSettings from its four constants and flags and passes `runsAppKitLoop: virtualDisplay`. Its output, flags, run loops and exit paths stay byte-identical.

EVIDENCE: I built a prototype at /private/tmp/claude-501/-Users-noah-Downloads-winstream/8c347207-ca84-4178-90e4-157cc440b6d8/scratchpad/d2proto. It is a copy of the package with the split and all of the above, plus macApp/.
- It was copied before the working tree gained `StreamServer(serviceType:advertise:)` and StreamCoordinator.swift:95 `StreamServer(advertise: !synthetic)`. Re-apply its changes on the current tree; do not copy its StreamServer.swift or StreamCoordinator.swift.
- `swift build -c release`: clean, no new warnings.
- CLI `--synthetic`: 60.0 fps through sillclient.py.
- The hand-written project passes `plutil -lint` and `xcodebuild -list` (it shows SillMac). An ad-hoc headless build: BUILD SUCCEEDED, the generated Info.plist merged with the partial one, the host code statically linked (otool shows only libSystem plus the Debug dylib).
- The app binary with `-SillSynthetic YES`: 59.8 fps.
- Live `defaults write` changes to bitrate, captureScale, maxFPS and virtualDisplay each gave exactly one "Settings: …" line and one restart, with new parameter sets about 40 ms later. Values checked:
  - 30 → 16 Mbps
  - 3024×1898 → 1512×948
  - 120 → 60 fps
  - the private API check (17 selectors) ran lazily when the virtual display was switched on
- SIGTERM ran the HostShutdown path.
- iOSClient/Sill.xcodeproj still builds for the simulator against the split package.

FOUND ALONG THE WAY:
1. MainActor.assumeIsolated traps under the CLI's dispatchMain(), because the main queue is then drained off the main thread. The prototype crashed on the first stats tick until the hook used Task { @MainActor }.
2. SceneBuilder rejects `if #available`, so `.defaultLaunchBehavior(.suppressed)` cannot guard a SwiftUI Window scene while the floor is macOS 14. That is why the Log window is AppKit.
3. Cross-process UserDefaults KVO fires only when a main run loop is running. The app has one; a process under dispatchMain does not.
4. NWListener.serviceRegistrationUpdateHandler reports the registered name ("Noah’s MacBook Pro"). A second host started at the same time got no registration callback within 3 s.

DISCLOSURE: before the tree's advertise-off-in-synthetic change landed, my prototype CLI hosts advertised on Bonjour, and Noah's iPad (iPad14,1) connected to them around 02:47–03:00. Some of the "moving wall" he saw may have been mine. Clean-up status:
- No process of mine is running.
- My scratch defaults domains (me.saffer.sill.d2proto and me.saffer.sill.d2kvotest) are deleted.
- ~/Library/Preferences/me.saffer.sill.d1prototest.plist is not mine; I left it.

Steps:
1. 0. Start from the current working tree, which changed during this design. It now has StreamServer.init(serviceType:advertise:) and StreamCoordinator.swift:95 `StreamServer(advertise: !synthetic)`. Do the file move while no other session is editing Sources/SillHost, because every later edit lands on the moved paths. Never commit.
1. 1. Split the package. `mkdir Sources/SillHostKit`, then move all 16 files of Sources/SillHost except main.swift into it: CursorShapeWatcher, EncoderProbe, EncoderSelfTest, HEVCEncoder, HostShutdown, InputInjector, Stats, StreamCoordinator, StreamServer, SyntheticCapture, VirtualDisplay, VirtualDisplaySelfTest, VirtualStage, WindowCapture, WindowCatalog and WindowSizer (.swift). Repoint the probe's symlink with `ln -sfn ../SillHostKit/VirtualDisplay.swift Sources/VirtualDisplayProbe/VirtualDisplay.swift`; VirtualDisplay stays internal and the probe compiles its own copy. In Package.swift:
- add `.library(name: "SillHostKit", targets: ["SillHostKit"])`
- add `.target(name: "SillHostKit", dependencies: ["StreamProtocol"])`
- change SillHost to `.executableTarget(name: "SillHost", dependencies: ["SillHostKit", "StreamProtocol"])`
The product name SillHost is unchanged, so `swift run -c release SillHost` still works.
1. 2. New file Sources/SillHostKit/HostSettings.swift: an `@MainActor @Observable public final class HostSettings`.
- Properties: `maxFPS: Int` (120), `captureScale: Double` (2), `bitrate: Int` (15_000_000, per 60 fps), `prioritizeSpeed: Bool` (false), `virtualDisplay: Bool` (false). The defaults equal today's main.swift:11-14 constants.
- `public struct Values: Equatable, Sendable` holding the same five fields.
- `public var values: Values`; reading it registers observation of every knob.
- The doc comment says who changes it: the app, live; the CLI, never.
1. 3. StreamCoordinator reads knobs (line numbers are in the current tree).
(a) Remove the `let`s maxFPS (:14), scale, bitrate, prioritizeSpeed (:28-30) and virtualDisplay (:42). Replace them with:
- `public let settings: HostSettings`
- `private var knobs: HostSettings.Values`
- `private var pendingKnobs: HostSettings.Values?`
- `private var settingsChangedWhileSwitching = false`
- `let runsAppKitLoop: Bool`
- computed `private var maxFPS { knobs.maxFPS }`, `private var scale: CGFloat { CGFloat(knobs.captureScale) }` and `private var virtualDisplay: Bool { knobs.virtualDisplay }`
This way :22, :27, :731 and the ~20 virtualDisplay branches stay untouched.
(b) :501 becomes `prioritizeSpeed: knobs.prioritizeSpeed`.
(c) init (:91) becomes `public init(settings: HostSettings, synthetic: Bool = false, runsAppKitLoop: Bool) throws`. It sets knobs = settings.values, forcing virtualDisplay off when !runsAppKitLoop.
(d) Move the private-API check at :177-187 into `checkPrivateAPIOnce()`. Call it from start and whenever the setting turns on; it also sets status.virtualDisplayUnavailable.
(e) `public func settingsChanged() async`:
```
guard !shuttingDown else { return }
var wanted = settings.values
if wanted.virtualDisplay && !runsAppKitLoop { wanted.virtualDisplay = false }
if wanted == knobs { pendingKnobs = nil; return }
pendingKnobs = wanted
if switching { settingsChangedWhileSwitching = true; return }
let leavingStage = knobs.virtualDisplay && !wanted.virtualDisplay && stage.isStaged
await select(active, bringForward: leavingStage)
```
(f) `private func applyPendingKnobs() async`, called in select between `server.resetForNewStream()` (:385) and `fps = effectiveFPS` (:386). If the virtual display goes from on to off: `await stage.leaveFullScreenIfNeeded(); stage.release()`, and mark the window for a fresh `catalog.resolveWindow(id:)` at :416 instead of the stale virtual-display snapshot. Then `knobs = new`, `catalog.preferMainDisplay = new.virtualDisplay`, `checkPrivateAPIOnce()` when on, and print one `Settings: <fps> fps ceiling, Retina|points capture, N Mbps per 60 fps, speed …, virtual display on|off` line.
(g) In select's defer (:361-377), after the viewport tail: `if settingsChangedWhileSwitching { settingsChangedWhileSwitching = false; Task { @MainActor in await self.settingsChanged() } }`.
(h) `activePID(trustAppKit:)` at :605 and :630 is passed `runsAppKitLoop` instead of virtualDisplay. For the CLI they are the same value, so the CLI is unchanged. The app always passes true.
(i) Optional: skip the restart when only virtualDisplay changed and the source is not a window, or only maxFPS changed and effectiveFPS == fps.
1. 4. Public surface. Only these, plus the new types; everything else stays internal.
- StreamCoordinator: `public final class`; `public init(settings:synthetic:runsAppKitLoop:)`; `public func start(preselect:) async`; `public private(set) var active`; `public var windowCount: Int { catalog.infos.count }` (main.swift must stop reaching into the catalog); `public let settings`; `public let status`; `public func settingsChanged() async`; `public func stayUpOnListenerFailure()`; `public func shutdownForExit()`.
- Stats: `public final class Stats`, `public static let shared`, `public func startPrinting()`, and a new `public var onTick: (([String: Int]) -> Void)?`, called on the main queue in tick() with the snapshot before printing.
- HostShutdown: `public enum`, `public static func install(coordinator:)`, and a new `@MainActor public static func quit(coordinator: StreamCoordinator?)`. quit does what begin does (the began guard, the "Shutting down…" line, a 3 s global-queue watchdog that calls exit(0), and `coordinator?.shutdownForExit()`) but does not call exit, because AppKit ends the process.
- `public` on EncoderSelfTest.run() and VirtualDisplaySelfTest.run().
1. 5. New file Sources/SillHostKit/HostLog.swift.
- `public final class HostLog: @unchecked Sendable` with `static let shared`.
- `public struct Line { id: Int (monotonic), date, text }`.
- A 5,000-line circular buffer under an NSLock.
- `public func lines(after id: Int) -> [Line]`.
- `public var onAppend: (() -> Void)?`, fired on the main queue at most every 250 ms.
- `public func startFile(at: URL)`: appends timestamped lines on a serial utility DispatchQueue (never on the network or capture queues), uses a cached formatter, and rotates to Sill.1.log at launch when the file is over 10 MB.
- `public func line(_ text: String)` for app code.
- The module-level shadow: `func print(_ items: Any..., separator: String = " ", terminator: String = "\n") { let text = items.map { "\($0)" }.joined(separator: separator); Swift.print(text, terminator: terminator); HostLog.shared.record(text) }`. Document at its definition that it shadows Swift.print for all of SillHostKit, so stdout is unchanged and any future print reaches the app's log. The explicit alternative, renaming the 94 call sites, is noted in risks.
1. 6. New file Sources/SillHostKit/HostStatus.swift: an `@MainActor @Observable public final class`.
- `advertisedName: String?`, `advertising: Bool` (false in synthetic mode), `listenerFailure: String?`, `virtualDisplayUnavailable: String?`.
- `clients: [Client]`, where Client has id: ObjectIdentifier, endpoint, and device/fps/rttMs from ClientStats.
- `stream: Stream?`: source, describe, width, height, fps, megabits, onVirtualDisplay, softwareEncoder.
- `encodedFPS`.
- Setters are `public internal(set)`. Do not mark the structs Sendable: StreamSource is not, and marking them produced warnings.

Wiring:
- StreamServer gets three callbacks:
  - `onClientStats: ((NWConnection, ClientStats) -> Void)?`: decode once at :180 and call it before the rate-limited print, keeping the print.
  - `onAdvertised: ((String) -> Void)?` via `listener.serviceRegistrationUpdateHandler = { if case .add(let ep) = $0, case .service(let name, _, _, _) = ep { onAdvertised?(name) } }`.
  - `onFailed: ((NWError) -> Void)?`: at :101-102, print as today, then call onFailed if set, else exit(1) as today.
- The coordinator updates status:
  - in onClientConnected, onClientDisconnected, onClientStats and onAdvertised (all through `Task { @MainActor }`)
  - at startPipeline success, next to the "Streaming …" print (:526)
  - in active's didSet (.none clears stream)
  - in checkPrivateAPIOnce
  - in Stats.onTick (`encodedFPS = counts["enc.out"] ?? 0`), always via `Task { @MainActor in … }` and never MainActor.assumeIsolated, which traps under dispatchMain (reproduced).
- `stayUpOnListenerFailure()` sets server.onFailed to write status.listenerFailure.
1. 7. InputInjector.launchingAppName (:449): when `Bundle.main.bundleURL.pathExtension == "app"`, return the bundle's name ("Sill"). Its parent is launchd, which today would print "enable launchd". Adjust the two messages to say "enable Sill" in that case. The CLI wording stays as it is.
1. 8. Sources/SillHost/main.swift:
- add `import SillHostKit`
- at :57-58: `let settings = HostSettings(maxFPS: maxFPS, captureScale: Double(scale), bitrate: bitrate, prioritizeSpeed: prioritizeSpeed, virtualDisplay: virtualDisplay)` and `let c = try StreamCoordinator(settings: settings, synthetic: synthetic, runsAppKitLoop: virtualDisplay)`
- at :63: `c.windowCount`
Everything else stays byte-identical: flags, self-tests, the preselect parsing, the .prohibited AppKit path, dispatchMain, and exit(1).
1. 9. Verify the CLI before any app work. `swift build -c release 2>&1 | grep -E "error|warning:|Build complete"` must show 0 errors and only the pre-existing Sources/CaptureProbe/main.swift:36 warning. Then run the synthetic check in the test plan (≥50 fps) and the other CLI flags.
1. 10. pbxproj surgery: macApp/Sill.xcodeproj/project.pbxproj, hand-written. Start from the prototype's file (d2proto/macApp/Sill.xcodeproj/project.pbxproj), which already builds.
Format:
- `objectVersion = 77`, `preferredProjectObjectVersion = 77`, `minimizedProjectReferenceProxies = 1` (Xcode 16+; Noah has 27).
- 21 objects with IDs 5111A0…0001 to …0015.
Objects:
- PBXProject, with packageReferences = XCLocalSwiftPackageReference `relativePath = ..`.
- A main PBXGroup (children: the synchronized group and Products).
- A Products group containing PBXFileReference Sill.app (explicitFileType wrapper.application, sourceTree BUILT_PRODUCTS_DIR).
- A PBXFileSystemSynchronizedRootGroup `path = Sill`, instead of per-file entries.
- A PBXFileSystemSynchronizedBuildFileExceptionSet with `membershipExceptions = (Info.plist)` targeting SillMac. Without it Info.plist would be copied as a resource and collide with the generated one.
- PBXNativeTarget SillMac: productName Sill, productType com.apple.product-type.application, fileSystemSynchronizedGroups = (Sill), packageProductDependencies = (SillHostKit, StreamProtocol).
- Empty Sources and Resources phases.
- A Frameworks phase with two PBXBuildFile entries whose productRef points at two XCSwiftPackageProductDependency objects (productName SillHostKit and StreamProtocol).
- Two XCConfigurationList and four XCBuildConfiguration objects.
Project-level settings: SDKROOT macosx, MACOSX_DEPLOYMENT_TARGET 14.0, DEVELOPMENT_TEAM 9B2KKVM937, DEAD_CODE_STRIPPING YES, ENABLE_USER_SCRIPT_SANDBOXING YES; Debug uses -Onone and DEBUG=1; Release uses wholemodule.
Target-level settings: PRODUCT_NAME Sill, PRODUCT_BUNDLE_IDENTIFIER me.saffer.sill.mac, CODE_SIGN_STYLE Automatic, CODE_SIGN_IDENTITY "Apple Development", ENABLE_HARDENED_RUNTIME YES, ENABLE_APP_SANDBOX NO, GENERATE_INFOPLIST_FILE YES, INFOPLIST_FILE Sill/Info.plist, INFOPLIST_KEY_LSUIElement YES, INFOPLIST_KEY_CFBundleDisplayName Sill, INFOPLIST_KEY_LSApplicationCategoryType public.app-category.utilities, INFOPLIST_KEY_NSHumanReadableCopyright, ASSETCATALOG_COMPILER_APPICON_NAME AppIcon, COMBINE_HIDPI_IMAGES YES, LD_RUNPATH_SEARCH_PATHS @executable_path/../Frameworks, MARKETING_VERSION 0.1, CURRENT_PROJECT_VERSION 1, SWIFT_VERSION 5.0, SWIFT_STRICT_CONCURRENCY minimal (mirroring iOS). No entitlements file: nothing needs one, and get-task-allow is added automatically in Debug.
The target is named SillMac rather than Sill so that a future root workspace holding both apps has no scheme clash. The product is still Sill.app with the executable Sill.
Validate with `plutil -lint` and `xcodebuild -list -project macApp/Sill.xcodeproj`. Commit only project.pbxproj and the scheme; Xcode generates project.xcworkspace, and the iOS project also commits only its pbxproj.
1. 11. Shared scheme macApp/Sill.xcodeproj/xcshareddata/xcschemes/SillMac.xcscheme (copy it from the prototype; it passes xmllint).
- BuildableReference: BlueprintIdentifier 5111A0000000000000000007, BuildableName Sill.app, BlueprintName SillMac, ReferencedContainer container:Sill.xcodeproj.
- Run uses Debug. It carries the launch argument `-SillSynthetic YES`, disabled by default.
- Profile and Archive use Release.
Command-line builds and Noah's Xcode then use the same scheme.
1. 12. App sources in macApp/Sill/. The synchronized folder picks them all up; the prototype has compiling versions of every file.
- SillApp.swift: `@main struct SillApp: App` with `@NSApplicationDelegateAdaptor(AppDelegate.self)`. Scenes: `MenuBarExtra { MenuContent(host:settings:) } label: { Image(systemName: host.menuSymbol) }.menuBarExtraStyle(.menu)` and `Settings { SettingsView(host:settings:) }`.
- AppDelegate.swift (@MainActor):
  - applicationDidFinishLaunching: `setvbuf(stdout, nil, _IOLBF, 0)`, `ProcessInfo.processInfo.disableAutomaticTermination(…)`, `.disableSuddenTermination()`, then `HostController.shared.start()`.
  - applicationShouldTerminate: `HostShutdown.quit(coordinator:)`, then return `.terminateNow`. This covers Quit, logout and Screen Recording's Quit & Reopen.
- HostController.swift (@MainActor @Observable singleton): `settings = SettingsStore.load()`. start() does:
  - `HostLog.shared.startFile(at:)`: ~/Library/Logs/Sill/Sill.log, or the `-SillLogFile` path
  - `synthetic = UserDefaults.standard.bool(forKey: "SillSynthetic")`
  - `try StreamCoordinator(settings:synthetic:runsAppKitLoop: true)`, then `stayUpOnListenerFailure()`
  - `HostShutdown.install { HostController.shared.coordinator }` (signals and atexit restore)
  - `Task { await c.start(preselect: nil); Stats.shared.startPrinting() }`
  - catch: store startError and show it in the menu; never exit
  - watchSettings(): `withObservationTracking { _ = settings.values } onChange: { Task { @MainActor in SettingsStore.save(…); await coordinator?.settingsChanged(); watchSettings() } }`. onChange fires in willSet, hence the hop.
  - install `SettingsStore.ExternalChanges`.
- SettingsStore.swift: `register(defaults:)` from `HostSettings()`, and load/save of the keys maxFPS, captureScale, bitrate, prioritizeSpeed and virtualDisplay. ExternalChanges is an NSObject that calls `addObserver(forKeyPath:)` on those keys, hops to the main actor and assigns only values that differ; that also stops the echo of the app's own save. QualityPreset offers 8, 15 (standard, today's value), 25 and 40 Mbps per 60 fps.
- MenuContent.swift, a real NSMenu in .menu style:
  - Status lines as Text items: "Advertising as “name”", "Registering on the local network…", "Not advertised: <error>" or "Synthetic test mode".
  - One line per client ("iPad (iPad14,1) · 60 fps · 6 ms") or "No devices connected".
  - "Streaming <describe>" and "W×H · <encoded> of <target> fps · N Mbps[ · virtual display]".
  - Divider, then Toggle Virtual Display, Picker Frame Rate Limit (60/120), Picker Quality, Picker Capture (Retina 2.0 / Points 1.0).
  - Divider, then a Permissions submenu and a Launch at Login toggle.
  - Divider, then Show Log…, and Settings… (⌘,) which calls `NSApp.activate()` and then `@Environment(\.openSettings)`.
  - Divider, then Quit Sill (⌘Q, `NSApp.terminate(nil)`).
- SettingsView.swift: a TabView of three grouped Forms.
  - General: launch at login plus an approve button, the advertised name, the log path.
  - Streaming: the virtual display toggle with its unavailable reason and a footer, segmented 60/120, quality, segmented Retina/Points, prioritize speed.
  - Permissions: rows with status and Allow…, plus Relaunch.
- Permissions.swift:
  - Status via `CGPreflightScreenCaptureAccess()` and `AXIsProcessTrusted()`.
  - Screen Recording: `CGRequestScreenCaptureAccess()`, which prompts once; otherwise open `x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture`.
  - Accessibility: `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])`, else `?Privacy_Accessibility`.
  - Refresh on menu open and on `NSApplication.didBecomeActiveNotification`. A 1 s Timer runs only while the Permissions tab is visible, so an idle host stays idle.
  - relaunch = `/bin/sh -c 'sleep 1; open "$0"' <bundle path>` plus `NSApp.terminate`.
- LoginItem.swift: `SMAppService.mainApp.register()`, `.unregister()` and `.status`; for `.requiresApproval`, `SMAppService.openSystemSettingsLoginItems()`. The system status is the truth, not UserDefaults. Show a caption when `Bundle.main.bundlePath` is not under /Applications.
- LogWindow.swift:
  - LogModel: `HostLog.shared.onAppend` bumps a version via `Task { @MainActor }`; hideStats (default true) filters the "[1s]" and "[30s]" lines.
  - LogTextView: an NSViewRepresentable wrapping `NSTextView.scrollableTextView()`, read-only, monospaced 11 pt; it appends `lines(after: lastID)` and keeps the view pinned to the bottom.
  - LogWindowController (AppKit): `NSWindow(contentViewController: NSHostingController(rootView: LogWindow(model:)))`, isReleasedWhenClosed false, setFrameAutosaveName; show() calls `NSApp.activate()` and then `makeKeyAndOrderFront`.
1. 13. Info.plist and assets.
- macApp/Sill/Info.plist is merged with the generated keys, like iOSClient/Info.plist. It holds NSLocalNetworkUsageDescription ("Sill makes this Mac visible to your iPhone and iPad on the local network."), NSBonjourServices [_sill._tcp], NSSupportsAutomaticTermination false and NSSupportsSuddenTermination false.
- macApp/Sill/Assets.xcassets/AppIcon.appiconset holds the 10 mac sizes, 16 to 512 pt at @1x and @2x. Render design/AppIcon.svg with `qlmanage -t -s 1024`, then `sips -z`. The prototype did this from the iOS 1024 PNG and produced AppIcon.icns.
- The real macOS icon is an Icon Composer AppIcon.icon built from the SVG's four layer groups (design/README.md). It goes in macApp/Sill/ with the same ASSETCATALOG_COMPILER_APPICON_NAME; this is a job for Noah in Icon Composer.
- The status item uses the SF Symbol `macbook.and.ipad` (verified present), or `exclamationmark.triangle` while a permission is missing, the listener failed, or startup failed. A template MenuBarIcon.imageset drawn from the icon's iMac and iPad outlines comes later.
1. 14. Verify the app headless, without signing prompts and without touching Noah's defaults domain. Build: `xcodebuild -project macApp/Sill.xcodeproj -scheme SillMac -configuration Debug -derivedDataPath <scratch>/dd CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PRODUCT_BUNDLE_IDENTIFIER=me.saffer.sill.test build`. Then run the synthetic app and the live-settings checks in the test plan, and afterwards `defaults delete me.saffer.sill.test` and remove its plist.
1. 15. Docs, not docs/BRIEF.md.
- CLAUDE.md, Layout: SillHostKit, HostSettings, HostStatus, HostLog, macApp/.
- CLAUDE.md, Build and run: the xcodebuild line, `-SillSynthetic YES` / `-SillLogFile`, `defaults write me.saffer.sill.mac <key>` live knobs, and that SIGTERM (not SIGINT) stops background test hosts. Also add a note: never MainActor.assumeIsolated from main-queue callbacks in SillHostKit.
- README, Mac host: the app, and that permissions are granted to "Sill", not Terminal.
- Also record the bundle ID decision (me.saffer.sill.mac, to be confirmed by Noah).
1. 16. Hand the project to Noah for the signed build, permissions and UI checks (see "For Noah" in the test plan). Once he has tried the virtual display, flipping its default to on is a one-line change in HostSettings' default.

Files: /Users/noah/Downloads/winstream/Package.swift, /Users/noah/Downloads/winstream/Sources/SillHost/main.swift, /Users/noah/Downloads/winstream/Sources/SillHostKit/StreamCoordinator.swift (moved from Sources/SillHost, edited), /Users/noah/Downloads/winstream/Sources/SillHostKit/StreamServer.swift (moved, edited), /Users/noah/Downloads/winstream/Sources/SillHostKit/Stats.swift (moved, edited), /Users/noah/Downloads/winstream/Sources/SillHostKit/HostShutdown.swift (moved, edited), /Users/noah/Downloads/winstream/Sources/SillHostKit/InputInjector.swift (moved, edited), /Users/noah/Downloads/winstream/Sources/SillHostKit/EncoderSelfTest.swift (moved, public run), /Users/noah/Downloads/winstream/Sources/SillHostKit/VirtualDisplaySelfTest.swift (moved, public run), /Users/noah/Downloads/winstream/Sources/SillHostKit/{CursorShapeWatcher,EncoderProbe,HEVCEncoder,SyntheticCapture,VirtualDisplay,VirtualStage,WindowCapture,WindowCatalog,WindowSizer}.swift (moved unchanged), /Users/noah/Downloads/winstream/Sources/SillHostKit/HostSettings.swift (new), /Users/noah/Downloads/winstream/Sources/SillHostKit/HostStatus.swift (new), /Users/noah/Downloads/winstream/Sources/SillHostKit/HostLog.swift (new), /Users/noah/Downloads/winstream/Sources/VirtualDisplayProbe/VirtualDisplay.swift (symlink retargeted to ../SillHostKit/VirtualDisplay.swift), /Users/noah/Downloads/winstream/macApp/Sill.xcodeproj/project.pbxproj (new, hand-written, objectVersion 77), /Users/noah/Downloads/winstream/macApp/Sill.xcodeproj/xcshareddata/xcschemes/SillMac.xcscheme (new), /Users/noah/Downloads/winstream/macApp/Sill/SillApp.swift (new), /Users/noah/Downloads/winstream/macApp/Sill/AppDelegate.swift (new), /Users/noah/Downloads/winstream/macApp/Sill/HostController.swift (new), /Users/noah/Downloads/winstream/macApp/Sill/SettingsStore.swift (new), /Users/noah/Downloads/winstream/macApp/Sill/MenuContent.swift (new), /Users/noah/Downloads/winstream/macApp/Sill/SettingsView.swift (new), /Users/noah/Downloads/winstream/macApp/Sill/Permissions.swift (new), /Users/noah/Downloads/winstream/macApp/Sill/LoginItem.swift (new), /Users/noah/Downloads/winstream/macApp/Sill/LogWindow.swift (new), /Users/noah/Downloads/winstream/macApp/Sill/Info.plist (new, partial; merged with generated keys), /Users/noah/Downloads/winstream/macApp/Sill/Assets.xcassets/ (new: Contents.json, AppIcon.appiconset; later AppIcon.icon and MenuBarIcon.imageset), /Users/noah/Downloads/winstream/CLAUDE.md (Layout, Build and run, conventions note), /Users/noah/Downloads/winstream/README.md (Mac host section: the app, permissions go to Sill), /Users/noah/Downloads/winstream/design/README.md (optional: macOS icon via Icon Composer, menu bar template glyph)

Risks:
- Hand-written pbxproj. A typo means Xcode says the project is damaged and won't open it.
- Mitigation: the objectVersion-77 synchronized folder keeps it to 21 objects and needs no edits when files are added. Before handover, check with `plutil -lint`, `xcodebuild -list` and a headless build. All three passed in the prototype.
- Residual: this format needs Xcode 16+.
- Residual: Xcode may re-serialize the file the first time Noah opens it or changes signing. Commit whatever it writes once.
- Residual: adding a new target or package product still needs manual edits.
- Two build systems compile SillHostKit: SwiftPM for the CLI and Xcode for the app.
- Xcode Debug builds compile the host at -Onone. Take performance numbers from the Release scheme (Profile) or the CLI.
- A warning can appear in one build and not the other. Build both before calling a change done.
- `public` churn is limited to what the CLI and the app call. Anything new the app needs from the host must be made public deliberately. `package` access cannot help, because Xcode app targets use a different -package-name.
- Threading trap (reproduced in the prototype): MainActor.assumeIsolated from a main-queue callback crashes the CLI under dispatchMain(), where the main queue is drained off the main thread. Every new main-queue hook in SillHostKit (Stats.onTick, HostLog.onAppend) must hop with Task { @MainActor }. The existing HostShutdown.begin is safe only because it is installed under NSApplication.run.
- Settings changes versus switches.
- The knob snapshot changes only inside select, and a change that arrives mid-switch is queued. Before these guards, a change could have been dropped by `guard !switching` (:359).
- Turning the virtual display off while a window is staged relies on applyPendingKnobs releasing the stage first, and on re-resolving the window. The catalog's SCWindow still carries the virtual-display frame, so the first encoder size could be wrong for one 2 s poll.
- The virtual display toggle with real windows is untested here: it needs Screen Recording and Accessibility.
- Regular-mode behavior changes in the app. activePID(trustAppKit:) becomes true in regular mode too, so NSWorkspace.frontmostApplication is trusted. The CLI is unchanged, since runsAppKitLoop equals its --virtual-display flag. This needs Noah to confirm that a first click into a background app's streamed window still lands.
- A window coming back from the virtual display is raised (bringForward) when the setting is turned off. That follows the 2026-09-23 rule that the Mac shows the picked window in regular mode, but it is a product call for Noah.
- SwiftUI behavior in an LSUIElement app, not verifiable here: this environment has no window-server connection for launched apps (lsappinfo shows !cgsConnection), so no menu or window rendering could be checked.
- The menu is .menu style. Its fps line may not refresh while the menu is open (known in older SwiftUI); it is current each time the menu opens.
- openSettings() may open the Settings window behind other apps. The design calls NSApp.activate() first. Fallback: bring the window whose identifier is com_apple_SwiftUI_Settings_window forward, or use an AppKit window as for the Log.
- A SwiftUI Window scene could auto-open at launch on macOS 14, and SceneBuilder rejects `if #available`, which is why the Log window is AppKit. The alternative is raising the app's floor to macOS 15 (Noah's call).
- TCC and signing.
- The .app is a new TCC identity, so Terminal's grants don't carry over.
- Apple Development signing keeps grants across rebuilds (expected designated requirement: identifier + anchor apple generic + leaf CN). Ad-hoc and headless test builds lose them.
- Developer ID (M6) changes the requirement, so grants must be given once more.
- Screen Recording needs a relaunch after granting, and macOS 15+ re-asks ScreenCaptureKit apps periodically.
- A Developer ID Application certificate needs the team's Account Holder.
- Local Network privacy on macOS 15+ applies to the app, where Terminal was exempt. If the prompt is denied, devices won't find or reach the Mac. NSLocalNetworkUsageDescription gives the prompt its text, but what exactly triggers it on macOS 27 is unverified.
- Bundle ID me.saffer.sill.mac is effectively permanent. TCC, Login Items, the defaults domain and future CloudKit all key off it. Noah should confirm it before the first grant.
- Launch at login registers whatever copy is running. A DerivedData build breaks on a clean. Enable it only from /Applications/Sill.app.
- CLI and app running at once.
- The second listener got no Bonjour registration callback within 3 s (observed), so it may never be advertised. The menu shows "Registering…", and after a timeout a hint that another host may be running.
- Both would use the same virtual-display identity (0x5111/1/1); the effect is unknown.
- The HostLog print shadow is implicit: a reader may not realize `print` also records. The alternative is an explicit rename of the 94 print call sites (Map 1's count), which is more churn and lets future prints bypass the app's log.
- The log file grows about 360 KB per streaming hour from the 1 s stats line, so it rotates at launch past 10 MB.
- The legacy appiconset rendered from the full-bleed iOS art may render oddly on macOS 26+. The proper fix is an Icon Composer .icon.
- Concurrent edits. The tree changed during this design (StreamServer advertise:). Moving 16 files conflicts with any other session editing Sources/SillHost, so do the move in one quiet step and re-apply the prototype's changes rather than copying them.
- Two Xcode projects now reference the same local package. The iOS build is verified. Xcode's GUI may complain if both are open at once (unverified). An optional root Sill.xcworkspace holding both projects avoids it, and the SillMac target name avoids a scheme clash.

Test plan:
- WITHOUT PERMISSIONS, build: `cd /Users/noah/Downloads/winstream && swift build -c release 2>&1 | grep -E "error|warning:|Build complete"`. Expect 0 errors and only the pre-existing CaptureProbe/main.swift:36 warning. This also builds VirtualDisplayProbe through the retargeted symlink. The prototype passed.
- WITHOUT PERMISSIONS, CLI synthetic:
1. Run `.build/release/SillHost --synthetic > <scratch>/cli.log 2>&1 &`.
2. Find the port: `lsof -nP -iTCP -sTCP:LISTEN -a -p <pid>`. The synthetic host no longer advertises, so no device will connect.
3. Run `python3 …/scratchpad/sillclient.py PORT 5 desktop`; expect 50+ fps (the prototype got 60.0).
4. Stop it with `kill -TERM <pid>`. Background jobs in a non-interactive shell ignore SIGINT.
5. Diff the log's line shapes against a pre-change run: the same lines, no "Settings:" line, no Advertised line.
- WITHOUT PERMISSIONS, CLI flags:
- `--encoder-selftest` exits 0 with the same report.
- `--virtual-display-selftest` creates and removes a display and exits 0.
- `--synthetic --virtual-display` streams under the AppKit loop and exits 143 on SIGTERM with the "Shutting down" line.
- A preselect argument (`--synthetic Safari`) is still parsed and harmlessly matches nothing.
- WITHOUT PERMISSIONS, project checks: `plutil -lint macApp/Sill.xcodeproj/project.pbxproj`, `xmllint --noout` on the scheme, and `xcodebuild -list -project macApp/Sill.xcodeproj`, which must list SillMac. The prototype passed all three.
- WITHOUT PERMISSIONS, headless app build:
1. Run the ad-hoc build from step 14 (the throwaway bundle ID me.saffer.sill.test); expect BUILD SUCCEEDED with no compiler warnings.
2. `plutil -p Sill.app/Contents/Info.plist` shows LSUIElement true, NSBonjourServices, NSLocalNetworkUsageDescription and LSMinimumSystemVersion 14.0.
3. `otool -L` shows no embedded frameworks.
4. Contents/Resources has AppIcon.icns.
- WITHOUT PERMISSIONS, app synthetic:
1. Run `<dd>/Build/Products/Debug/Sill.app/Contents/MacOS/Sill -SillSynthetic YES -SillLogFile <scratch>/sill.log > <scratch>/app.log 2>&1 &`.
2. Find the port with lsof, then run `sillclient.py PORT 5 desktop`; expect 50+ fps (the prototype got 59.8).
3. <scratch>/sill.log has timestamped lines.
4. `kill -TERM` exits via HostShutdown ("Shutting down…"), and nothing of yours is left running.
- WITHOUT PERMISSIONS, live settings, same app run with `sillclient.py PORT 13 desktop --fps=120`:
- `defaults write me.saffer.sill.test bitrate -int 8000000` gives one "Settings:" line and "Streaming … 120 fps, 16 Mbps".
- `captureScale -float 1` gives 1512×948.
- `maxFPS -int 60` gives 60 fps, 8 Mbps.
- `virtualDisplay -bool YES`, then NO, gives the private-API line (17 selectors) and a restart each.
- The client sees new parameter sets about 40 ms after each change.
- Clean up with `defaults delete me.saffer.sill.test` and remove the plist.
The prototype reproduced all of this.
- WITHOUT PERMISSIONS, iOS unaffected: `xcodebuild -project iOSClient/Sill.xcodeproj -scheme Sill -destination 'generic/platform=iOS Simulator' -derivedDataPath <scratch>/dd-ios CODE_SIGNING_ALLOWED=NO build` gives BUILD SUCCEEDED. The prototype passed.
- FOR NOAH, first launch:
1. Open macApp/Sill.xcodeproj. Signing & Capabilities should show team 9B2KKVM937, certificate Apple Development, and no profile required.
2. ⌘R. Expect a status item with the macbook.and.ipad glyph, no Dock icon, not in ⌘Tab, and no window at launch.
3. The Accessibility prompt names Sill; grant it.
4. At the first capture, the Screen Recording prompt names Sill; grant it.
5. Use Quit & Reopen. The log shows "Shutting down…" and the app comes back with both permissions allowed.
6. Answer the Local Network prompt if it appears, and note whether it did.
- FOR NOAH, the menu:
1. It shows "Advertising as “Noah’s MacBook Pro”".
2. Connect the iPad: "iPad (iPad14,1) · 60 fps · N ms" appears within 1 s.
3. Pick a window: "Streaming <app — title>" and "W×H · ~60 of 60 fps · 15 Mbps" appear.
4. Quit the iPad app: the line goes and the stream stops.
- FOR NOAH, controls while streaming a real window. Each control should give one "Settings:" line and one "Capture started" line:
- Quality: Mbps changes.
- Capture Points: half the pixels.
- 60 fps limit on a 120 Hz device: 60.
- Virtual Display on: "Virtual display … created", "Moved …", and the frame fills the panel.
- Virtual Display off: "Restored …", "Removed virtual display", the window back within 2 pt and in front, and no "Sill" display left in System Settings › Displays.
- FOR NOAH, Settings (⌘, from the menu) opens in front with General, Streaming and Permissions tabs. Changes mirror the menu instantly. Quit and relaunch: the values persist. `defaults read me.saffer.sill.mac` shows the keys.
- FOR NOAH, the log: Show Log… opens in front and lines stream in. "Hide Stats Lines" toggles the 1 s counters. Selecting and copying works. `tail -f ~/Library/Logs/Sill/Sill.log` matches the window.
- FOR NOAH, permissions: revoke Accessibility in System Settings. Reopening the menu shows "Allow Accessibility…" and the status item turns into the warning triangle. Allow… opens the right pane. Re-grant: the state updates without a relaunch. Screen Recording shows "Relaunch Sill to Apply" after Allow….
- FOR NOAH, quit with a window staged on the virtual display: via the menu, via ⌘Q from the Settings window, and via `killall -TERM Sill`. Each time the window returns to its original frame and the "Sill" display disappears.
- FOR NOAH, rebuild in Xcode (edit a comment, ⌘R). Screen Recording and Accessibility must still be granted: the Apple Development requirement is stable. Optionally, contrast with the ad-hoc build from the test step, which is not granted.
- FOR NOAH, launch at login: copy a build to /Applications/Sill.app and turn on Launch at Login. System Settings › General › Login Items lists Sill. Log out and back in: Sill starts, advertises, and the iPad finds it.
- FOR NOAH, regular-mode input under the app (trustAppKit is now true): from the iPad, click into a streamed window whose app is in the background. The app activates and the click lands; the log shows "Click at … → the streamed window". Type into it.
- FOR NOAH, run the CLI while the app runs and note what the menu shows (registration missing?) and which one the iPad finds. This is informational and feeds the "another host" hint.
- FOR NOAH, footprint: idle with no client, `ps -o %cpu,rss -p $(pgrep -x Sill)` should be about 0.0 % CPU with one 30 s heartbeat line. Note the RSS against the CLI's 36 MB. Streaming a Retina window should be about 3 %, as with the CLI; measure a Release build.

### Design 1: Sill.app menu bar host: runtime model, menu and Settings UX, HostSettings, Quit (designer 3)

One host core, two thin shells. The CLI keeps its exact paths, flags and stdout. Sill.app is the CLI's existing --virtual-display branch (NSApplication.run, main.swift:74-83) with activation policy .accessory (LSUIElement), plus an AppDelegate that owns a status item, a Settings window and a Log window. StreamCoordinator, StreamServer, VirtualStage and Stats run underneath; the pipeline knows nothing about the UI.

Settings in two layers:
- HostConfig: a value type (maxFPS, captureScale, bitrate, prioritizeSpeed, virtualDisplay). The coordinator builds pipelines from it. The CLI makes one from its knobs and flags and never touches UserDefaults.
- HostSettings: @Observable, app only. The menu and Settings edit it; it persists to UserDefaults and pushes each change into coordinator.apply(_:).

The coordinator deliberately does not read the observable live. virtualDisplay is read mid-session at about 15 sites: windowCommand :211, input mapping :262, raise/evict :593-605, windowsChanged :794-814. Flipping it under a staged window would map input to the wrong rectangle and loop restarts. So apply() queues the config and select() commits it once the old pipeline is down. That is the critical section that already owns restarts; pendingConfig behaves like viewportArrivedWhileSwitching. A restart happens only when the running stream would actually change.

When a change takes effect:
- Immediately, no restart: Launch at login; any change while nothing streams (the next pick uses it); a frame-rate limit that doesn't change the effective rate; the virtual display while the Desktop streams.
- One restart of the current source (about 0.3-1 s freeze, then a keyframe): frame-rate limit when the effective rate changes; quality; resolution; encoding speed; the virtual display while a window streams. Turning it on moves the window to the virtual display; turning it off returns it to its original frame.
- Launch-time only: --synthetic, and CLI vs app. Since a concurrent edit today, --synthetic also means 'not advertised' (StreamCoordinator.swift:95).

UI technology:
- Menu: AppKit NSStatusItem + NSMenu with an NSMenuDelegate. menuWillOpen/menuDidClose gate every refresh, so the idle host stays at 0 % CPU with only the Stats heartbeat. The live status block is a SwiftUI view in NSMenuItem.view; the controls are standard NSMenuItems.
- Settings: an AppKit-owned window, NSTabViewController with .toolbar tabs, whose panes are SwiftUI Forms (.formStyle(.grouped)). It looks the same as a SwiftUI Settings scene.
- Why not the Settings scene itself: on macOS 14+ it opens only via SettingsLink/openSettings from inside SwiftUI. The old showSettingsWindow: action reportedly just logs a warning (I did not re-test this on 27). That forces either MenuBarExtra(.menu), which has no open/close hooks and adds a second app lifecycle next to main.swift, or a hidden-window bridge. If Noah prefers the scene anyway: MenuBarExtra(.menu) + SettingsLink + Window('Log'), calling NSApp.activate() when a window appears.
- Logging: a module-level print shadow routes the 94 existing call sites into a HostLog ring buffer, and in the app also into ~/Library/Logs/Sill/Sill.log. The CLI's stdout stays byte-identical.

Verified in scratch code ($SP = /private/tmp/claude-501/-Users-noah-Downloads-winstream/8c347207-ca84-4178-90e4-157cc440b6d8/scratchpad; I did not edit the repo):
1. The print shadow catches the module's own calls and no one else's. @Observable keeps didSet. package access works across targets with tools 5.9. ($SP/d3probe)
2. Every AppKit, SwiftUI and ServiceManagement API named here typechecks at the macOS 14.0 floor, except NSMenuItem.subtitle, which needs 14.4. ($SP/d3api.swift)
3. While a status menu opened by a click is tracking, main.async blocks, Task { @MainActor } hops and main-queue timers keep running, so the host doesn't pause. A SwiftUI card inside the menu re-rendered 9 times in 2 s. ($SP/d3track.swift, d3card.swift)
4. A nested modal loop started from inside a Task { @MainActor } starves all of those: 0 of 10 ran. This covers menu popUp, runModal, and terminate with .terminateLater. An async terminate reply arrives after 0.81 s when terminate comes from an event, and never when it comes from a Task. ($SP/d3track2.swift, d3quit.swift)
5. Settings panes render offscreen with real controls, in light and dark, without Screen Recording. ($SP/pane-light.png, pane-dark.png)
6. The menu bar glyph can be drawn in code from AppIcon.svg's geometry as a template image with 4 states, so no rasterising is needed. ($SP/glyph/preview.png) The fallback SF Symbol macbook.and.ipad exists on this Mac.
7. No App Nap or power assertion exists anywhere today. The CLI was never subject to App Nap; a windowless accessory app is.

Build approach, only as far as the UX needs it. The UX needs:
- an icon in the bundle, which shows in Privacy & Security and Login Items;
- a designated requirement that survives rebuilds, so grants persist: sign the whole bundle with the Apple Development identity, not ad hoc;
- a stable install path for the login item: ~/Applications/Sill.app;
- the CLI's test flags available in the app.
Both options satisfy these. I lean to (a), SwiftPM + Scripts/make-app.sh with a SillHostKit library and package access; an Xcode project would need public on the same symbols. The paths below assume (a); nothing else depends on the choice.

Working tree: during this run StreamServer.swift:82-100 (advertise:) and StreamCoordinator.swift:95 changed, on top of the earlier uncommitted Launch Services removal. Build on the working tree. All line numbers here are the working tree's.

Steps:
1. 1. Lock identity and layout (Noah decides, before any code).
- CFBundleIdentifier: proposal me.saffer.sill.mac. TCC grants, SMAppService, the UserDefaults domain and M5 iCloud all key off it, so it must not change after the first grant.
- Display name 'Sill', executable 'Sill'.
- Virtual display default in the app: Off, like the CLI (main.swift:24-28). Flip both together.
- Layout (a): git mv every Sources/SillHost/*.swift except main.swift to Sources/SillHostKit/.
- Package.swift: .target(name: "SillHostKit", dependencies: ["StreamProtocol"]); .executableTarget(name: "SillHost", dependencies: ["SillHostKit"]) holding main.swift only; .executableTarget(name: "SillApp", dependencies: ["SillHostKit"]) with product .executable(name: "Sill", targets: ["SillApp"]).
- Repoint the Sources/VirtualDisplayProbe/VirtualDisplay.swift symlink to ../SillHostKit/VirtualDisplay.swift.
- Mark `package`: StreamCoordinator (both inits, start, apply, active, catalog, statusSnapshot, onStatusChanged, prepareForQuit, shutdownForExit); HostConfig; HostStatusSnapshot and its parts; HostLog; Stats.shared, startPrinting and lastSecond; HostShutdown.install; EncoderSelfTest.run; VirtualDisplaySelfTest.run; VirtualDisplay.checkPrivateAPI.
1. 2. New Sources/SillHostKit/HostConfig.swift.
- struct HostConfig: Equatable, Sendable { var maxFPS: Int; var captureScale: CGFloat; var bitrate: Int; var prioritizeSpeed: Bool; var virtualDisplay: Bool }.
- static let standard = HostConfig(maxFPS: 120, captureScale: 2, bitrate: 15_000_000, prioritizeSpeed: false, virtualDisplay: false). The knob values move here from main.swift:11-14, so the CLI and the app's registered defaults share one source.
- validated(): maxFPS 24...120, captureScale 1 or 2, bitrate 2-100 Mbps.
- changes(to:) -> String, for the log line (e.g. 'frame rate limit 120 → 60 fps').
- enum QualityPreset: Int, CaseIterable { case efficient = 8_000_000, balanced = 15_000_000, high = 30_000_000 }, labelled 'Efficient — 8 Mbps', 'Balanced — 15 Mbps', 'High — 30 Mbps'. Any other stored bitrate shows as 'Custom — N Mbps'.
1. 3. StreamCoordinator consumes config snapshots.
- Replace the lets at :14, :28-30 and :42 with `private(set) var config: HostConfig` and computed maxFPS, scale, bitrate, prioritizeSpeed and virtualDisplay returning config.x. Every existing read (:22, :27, :501, :731 and the ~15 virtualDisplay sites) keeps its text. synthetic stays a let.
- Add `let appKitLoop: Bool` and pass it to activePID(trustAppKit:) at :605 and :630 instead of virtualDisplay. The CLI passes its --virtual-display flag, so it is identical; the app passes true.
- New designated init(config:synthetic:appKitLoop:onListenerFailed:). Keep today's init at :91 as a convenience that builds a HostConfig with appKitLoop = virtualDisplay.
- Move the private-API check (:177-187) into an idempotent enableVirtualDisplay(). It runs at start when the setting is on, and on each off→on. It prints as today, sets catalog.preferMainDisplay = true (today only at :97), and clears a loss-count disable (stageLosses = 0; stage.disabledReason = apiProblem).
- apply(_ new: HostConfig) async: set pendingConfig = new.validated(). If switching or shuttingDown, return (the defer re-applies). If active == .none or !restartNeeded(new), commit now. Otherwise await select(active).
- In select, insert `await commitPendingConfig()` between server.resetForNewStream() (:385) and fps = effectiveFPS (:386): after capture and encoder are down, before the virtual display block at :388.
- commitPendingConfig(): on virtual display on→off with a stage, run `await stage.leaveFullScreenIfNeeded(); stage.release(); await catalog.refreshWindows()`. The release must happen while the flag still reads on, because :388 is skipped afterwards. The refresh gives the .window lookup at :415 the window's home frame. Then assign config; call enableVirtualDisplay() on off→on; print 'Settings: <changes>; restarting <source>'; call onStatusChanged?().
- In the defer (:361-377), after the two existing flags: `if let p = pendingConfig { Task { @MainActor in await self.apply(p) } }`.
- restartNeeded(new) is true when any of these differ: the effective fps, i.e. min(new.maxFPS, highest client rate), capped at 60 on the software encoder; the effective capture scale (min(scale,1) on software); bitrate; prioritizeSpeed; or virtualDisplay while active is .window.
- start(preselect:promptForAccessibility: Bool = true, readWindows: Bool = true). The app passes false and CGPreflightScreenCaptureAccess(). That way the first ScreenCaptureKit call (:190), which raises the system Screen Recording alert, follows the user's click in the Permissions pane rather than launch. ensureAccessibility (:167) likewise waits for the user.
1. 4. Status surface, pulled only while the menu is open, so a closed menu costs nothing.
- StreamCoordinator:
  - private(set) var streamInfo: StreamInfo?, set beside the print at :526 and cleared when active becomes .none. Fields: kind (window, desktop or synthetic), app and title, width, height, fps, streamBitrate, onVirtualDisplay (sourceRect != nil), software.
  - private(set) var lastStageFailure: String?, from the catch at :433-437.
  - var onStatusChanged: (() -> Void)?, called from active.didSet (:66), onClientCountChanged (:121), the encoder fallbacks (:173, :759), config commits and listener state.
  - func statusSnapshot() -> HostStatusSnapshot. New Sources/SillHostKit/HostStatus.swift holds the snapshot: network (starting, advertising(name), notAdvertised(port) for --synthetic, waiting, failed(error, retryIn)), devices, source, encodedFPS, softwareEncoder, virtualDisplayProblem, lastStageFailure, synthetic.
- StreamServer.swift:
  - Store every decoded ClientStats and its time in Client. The branch at :175-183 still prints every ~2 s as now.
  - func clientSummaries() -> [ClientSummary] via queue.sync. This is main→network only; nothing on the network queue syncs to main.
  - serviceRegistrationUpdateHandler records the name Bonjour actually registered ('… (2)' when another host holds the name). Expose listener.port for synthetic mode.
  - onStateChanged (ready, waiting, failed).
  - init(serviceType:advertise:onListenerFailed:), keeping today's advertise parameter. With no handler, .failed prints and calls exit(1) exactly as :102 does now. The app's handler rebuilds the NWListener with the same parameters after 2, 5 and 15 s, then every 30 s. Connected devices keep their NWConnections.
  - stopAdvertising() cancels the listener.
- Stats.swift: keep the last completed second's counters (lastSecond, set in tick at :92) so the menu shows enc.out as the real encoded fps. Printed output is unchanged.
1. 5. New Sources/SillHostKit/HostLog.swift.
- final class HostLog: @unchecked Sendable, with state under an NSLock like Stats.
- A ring of the last 5,000 lines (seq, Date, text). It is off until a shell calls keepLines(); the CLI never does, so it pays one bool check per print.
- openFile(_:) (app only): ~/Library/Logs/Sill/Sill.log, each line prefixed 'yyyy-MM-dd HH:mm:ss.SSS ', renamed to Sill.1.log past 10 MB. Writes go through a serial utility queue, so the capture, VideoToolbox and network threads never touch the disk.
- var onAppend: (() -> Void)?, set by the Log window only while it is open. Coalesced to one main-queue call per 100 ms.
- Route every existing print through it with a shadow in the same file: `func print(_ items: Any..., separator: String = " ", terminator: String = "\n") { let s = items.map { String(describing: $0) }.joined(separator: separator); Swift.print(s, terminator: terminator); HostLog.shared.append(s) }`. All 94 call sites stay untouched and the CLI's stdout is byte-identical (verified in scratch).
- SillApp gets the same three-line shadow for its own prints. Document the shadow where it is declared.
1. 6. Sources/SillHost/main.swift (the CLI) keeps its behaviour.
- import SillHostKit.
- The four knob lets (:11-14) become `var config = HostConfig.standard`, with a comment that the knobs now live in HostConfig.standard and that the app's Settings start from the same values. Then `config.virtualDisplay = virtualDisplay`.
- :57 either calls StreamCoordinator(config: config, synthetic: synthetic, appKitLoop: virtualDisplay) or keeps the old call through the convenience init.
- Unchanged: flags, preselect, both self-tests, CGMainDisplayID priming, the dispatchMain/NSApplication split, HostShutdown only under --virtual-display, the Terminal permission hint and exit(1). The CLI never reads UserDefaults, never opens the log file, and never builds HostSettings.
1. 7. App shell and runtime rules.
- Sources/SillApp/main.swift, in order: setvbuf(stdout, nil, _IOLBF, 0); open the log file (-SillLogFile overrides the path) and call keepLines(); honour --encoder-selftest and --virtual-display-selftest (their output also lands in the file, which helps diagnose the app's own TCC identity); `_ = CGMainDisplayID()`; then `let app = NSApplication.shared; app.setActivationPolicy(.accessory); app.delegate = delegate; app.mainMenu = MainMenu.make(); app.run()`.
- MainMenu.swift: an accessory app shows no menu bar but still needs one for key equivalents. Build Sill (About Sill, Settings… ⌘,, Quit Sill ⌘Q), Edit (Undo, Redo, Cut, Copy, Paste, Select All, Find ▸ Find… ⌘F / Find Next ⌘G via performFindPanelAction:) and Window (Minimize ⌘M, Close ⌘W). Without it, ⌘C, ⌘A, ⌘F and ⌘W do nothing in the Log and Settings windows.
- AppDelegate.applicationDidFinishLaunching:
  - Install the status item first, showing 'Starting…'.
  - Always call HostShutdown.install { coordinator }, because the virtual display can be switched on at runtime.
  - Then in a Task @MainActor: create HostSettings; create StreamCoordinator(config: settings.config, synthetic:, appKitLoop: true, onListenerFailed:); in the same main-actor turn set settings.onChange = { cfg in Task { await coordinator.apply(cfg) } }; set coordinator.onStatusChanged to refresh the icon and App Nap state; await coordinator.start(preselect: nil, promptForAccessibility: false, readWindows: CGPreflightScreenCaptureAccess()); call Stats.shared.startPrinting(); log a start line; run the onboarding check (step 12).
- App Nap: while catalog.clientCount > 0, hold ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical], reason: "Sill is serving a connected device"). End it at 0 clients.
- applicationShouldHandleReopen(_:hasVisibleWindows:) shows Settings. Double-clicking Sill.app is the way back if macOS hides the status item.
- Rule for the whole app target (verified): never start a nested modal loop from Task { @MainActor }, a @MainActor async continuation or a DispatchQueue.main block. That covers NSMenu.popUp, NSAlert.runModal, NSApp.runModal, and NSApp.terminate when it can return .terminateLater. The serial main queue would stop every Task hop the host makes (input, client messages, selects, Stats) for as long as the loop runs. Start them only from AppKit target/action, SwiftUI actions or a run-loop Timer, and show errors inline rather than in alerts.
1. 8. Sources/SillApp/HostSettings.swift.
- `@MainActor @Observable final class HostSettings { var config: HostConfig { didSet { guard config != oldValue else { return }; save(); onChange?(config) } }; @ObservationIgnored var onChange: ((HostConfig) -> Void)? }`. didSet on an @Observable property is verified.
- One UserDefaults key per field, so `defaults write me.saffer.sill.mac bitrate -int 20000000` still serves Noah's change-and-measure loop: maxFPS (Int, 60 or 120), captureScale (Double, 2 or 1), bitrate (Int, bit/s per 60 fps), prioritizeSpeed (Bool), virtualDisplay (Bool).
- register(defaults:) from HostConfig.standard; load through validated(). Because it reads UserDefaults.standard, launch arguments override for one run without persisting (e.g. -maxFPS 60 -bitrate 8000000).
- UI-only keys: settingsTab, permissionsOnboardingDismissed, askedScreenRecording, askedAccessibility, logShowsStats.
- Launch at login is not stored here; SMAppService is its source of truth.
- Panes bind via @Bindable ($settings.config.maxFPS); menu actions set settings.config directly. Both go through didSet, so there is one path to the coordinator.
- No sliders or other continuous controls: each change is one apply and at most one restart.
1. 9. Status item and menu: StatusItemController.swift, StatusGlyph.swift, StatusCard.swift.
- Status item: NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength), autosaveName 'SillStatusItem', button image StatusGlyph.image(state) (template, 18 pt), toolTip 'Sill — <header>', and an accessibility label per state.
- Glyph: port $SP/glyph/glyph.swift, which draws AppIcon.svg's own geometry with NSBezierPath: the iMac body (672×456, r60) stroked, the neck and foot filled, and the iPad (408×300, r48) tilted −5° about (520,392) with a cleared margin and a knocked-out screen. States: idle (empty iPad), connected (small dot on the iPad), streaming (a window fills the iPad), attention (knocked-out dot at the lower right). Fallback: SF Symbol macbook.and.ipad.
- The icon is event-driven via onStatusChanged; nothing polls while the menu is closed.
- The menu (delegate = self, autoenablesItems = false), top to bottom:
  a. A status card: one NSMenuItem whose view is NSHostingView(rootView: StatusCard(model:)), 300 pt wide, fed by an @Observable StatusModel. It shows the header, the source row, and one row per device (ipad or iphone symbol, chosen from the ClientStats device string).
  b. Attention items, only when needed: enabled items with a non-template orange exclamationmark.triangle.fill.
  c. Separator; 'Virtual Display' (checkmark state); 'Frame Rate' ▸ 'Up to 60 fps' / 'Up to 120 fps'; 'Quality' ▸ the presets; 'Resolution' ▸ 'Retina' / 'Standard'.
  d. Separator; 'Launch at Login' (checkmark state); 'Permissions' ▸ 'Screen Recording: Allowed' or 'Screen Recording: Not Allowed…', 'Accessibility: …', separator, 'Open Privacy & Security…'.
  e. Separator; 'Show Log…'; 'Settings…' ⌘,.
  f. Separator; 'Quit Sill' ⌘Q.
- Explanations go in NSMenuItem.subtitle under `if #available(macOS 14.4, *)`, with toolTip as the fallback.
- menuWillOpen: re-read CGPreflightScreenCaptureAccess(), AXIsProcessTrusted() and SMAppService.mainApp.status; load coordinator.statusSnapshot(); start a 1 s DispatchSourceTimer on .main that refreshes StatusModel.
- menuDidClose: cancel the timer.
1. 10. Status copy: Sources/SillApp/StatusText.swift.
- A pure function: StatusText.present(snapshot, permissions, synthetic) -> StatusPresentation (glyph state, header, subtitle, source row, device rows, attention items, tooltip). The card, icon and tooltip all use it.
- Log 'Status: <header> — <subtitle>' whenever the header changes.
- Capitalization: title case in menus, sentence case in explanations, typographic quotes.
- Header, first match wins:
  - 'Starting…'
  - 'Sill Couldn’t Start' / '<error>'
  - 'Not Visible on the Network' / '<error>. Retrying in 5 s.'
  - 'Waiting for a Network' / 'Sill appears on your iPhone and iPad once this Mac is on Wi-Fi or Ethernet.'
  - 'Test Pattern Mode' / 'Not advertised on the network; test clients connect to port <port>.' (--synthetic)
  - 'Screen Recording Is Off' / 'Devices can connect but can’t see any windows.'
  - 'Streaming to iPad' or 'Streaming to 2 Devices'
  - 'iPad Connected' or '2 Devices Connected' / 'Pick a window on the device to start streaming.'
  - 'Waiting for a Device' / 'Open Sill on your iPhone or iPad. This Mac appears as “<registered name>”.'
- Source row:
  - Title: 'Safari — Apple Developer' (app — title, 44 characters, truncated in the middle), 'Whole Desktop' or 'Test Pattern'.
  - Subtitle: '3024×1898 · 118 of 120 fps · 30 Mbps · virtual display'. Use '120 fps, nothing changing' when enc.out was 0 in the last second. Append ' · software encoder' when on it, and ' · real window (virtual display: <reason>)' after a stage fallback.
- Device row: 'iPad (iPad14,1)' (the endpoint host until the first report arrives, within 1 s) / '118 fps · frame age 9 ms · RTT 7 ms'; 'No report for 5 s' when stale.
- Attention items:
  - 'Allow Screen Recording…' / 'Needed to show your windows on your devices.'
  - 'Allow Accessibility…' / 'Devices can watch but not click or type.'
  - 'Hardware Encoder Not Responding' (disabled) / 'Streaming with the software encoder, up to 60 fps. Restarting the Mac fixes this.'
- Virtual Display subtitle: 'The streamed window is on the virtual display' / 'Unavailable: <reason>' / 'Picked windows leave this screen while they stream'.
- Launch at Login subtitle, when approval is pending: 'Approve Sill in System Settings › Login Items'.
- Glyph: attention for missing permissions or a network failure; otherwise streaming, connected or idle.
1. 11. Settings window: SettingsWindow.swift and SettingsPanes.swift.
- An NSWindowController with NSWindow(contentViewController: tabs), where tabs.tabStyle = .toolbar. One NSTabViewItem(viewController: NSHostingController(rootView: pane)) per tab, each with sizingOptions = [.preferredContentSize] and a symbol image.
- setFrameAutosaveName("SillSettings"); collectionBehavior .moveToActiveSpace; width 520 pt; always opened on the primary screen, never on the virtual display. Opened from the menu item or reopen via showWindow + NSApp.activate().
- Panes are SwiftUI Form with .formStyle(.grouped), sentence case. The Streaming pane is drafted at $SP/pane-light.png and pane-dark.png.
- General (gearshape):
  - 'Launch at login' toggle, with an inline 'Approve in System Settings…' when pending.
  - 'Visible on your network as “<name>”', with 'To change the name, open System Settings › General › Sharing.' and a link button.
  - 'Show Log…' and 'Reveal Log File'.
  - A version footer.
- Streaming (play.rectangle):
  - 'Frame rate limit': segmented 60 fps | 120 fps.
  - 'Quality' picker.
  - 'Resolution' picker: Retina | Standard.
  - Footer: 'Each device asks for its own screen’s rate, up to this limit. Quality is per 60 fps; a 120 fps stream gets twice as much. Changes apply at once: the current stream restarts for a moment.'
  - 'Prioritize encoding speed' toggle, with 'Lower latency when the Mac is busy, at a softer picture.'
  - On the software encoder: 'The hardware encoder isn’t responding, so streams are limited to 60 fps at Standard resolution until the Mac restarts.'
- Virtual Display (display):
  - Toggle 'Stream from a virtual display'.
  - 'Sill moves the window you pick onto an invisible display made for your device, so it keeps updating when other windows cover it and text is drawn at your device’s scale. The window leaves this screen while it streams and comes back when you stop streaming or quit Sill.'
  - Status row: 'Available' / 'Not available on this version of macOS' / 'Needs Screen Recording and Accessibility' / 'Off for this session: macOS removed the display 3 times', with a 'Try Again' button that calls enableVirtualDisplay() and restarts.
  - Footer: 'Uses a private macOS interface (CGVirtualDisplay). If a macOS update breaks it, Sill streams the window where it is.'
- Permissions (lock.shield): see step 12.
- Panes that show permission or login status refresh on a 1 s timer only while visible (onAppear/onDisappear), and on NSApplication.didBecomeActiveNotification.
1. 12. Permissions and first launch: Permissions.swift and the Permissions pane.
- Screen Recording row: 'Lets Sill capture the windows you pick on your iPhone or iPad. Nothing is recorded or saved; frames go straight to your devices on this network.'
- Accessibility row: 'Lets your iPhone or iPad click, scroll and type on this Mac, and lets Sill move and size the window it streams.'
- Footer: 'Access belongs to Sill itself. Access you gave Terminal for the SillHost command-line tool doesn’t carry over.'
- Each row shows a green checkmark.circle.fill 'Allowed', or an orange warning plus one button.
- Screen Recording flow:
  - Status: CGPreflightScreenCaptureAccess().
  - Not yet asked: 'Allow…' calls CGRequestScreenCaptureAccess() and sets askedScreenRecording.
  - Already asked: 'Open System Settings' opens x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture, then 'Relaunch Sill' appears, because the grant only takes effect in a new process. macOS's own 'Quit & Reopen' arrives through the normal Quit path.
  - Relaunch: a Process running `/bin/sh -c 'while /bin/kill -0 <pid>; do /bin/sleep 0.2; done; /usr/bin/open "<bundle path>"'`, then NSApp.terminate(nil) from the button action.
- Accessibility flow:
  - Status: AXIsProcessTrusted(). It takes effect live, with no relaunch.
  - 'Allow…' calls AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true]); after that, 'Open System Settings' opens …?Privacy_Accessibility.
- When both are allowed: 'You’re all set. Open Sill on your iPhone or iPad.' followed by the Launch at login toggle.
- Onboarding rule:
  - At launch, if a permission is missing, the app is not in --synthetic mode, and permissionsOnboardingDismissed is false, open Settings on this tab and activate the app.
  - A user close (windowShouldClose, not termination) while something is still missing sets the flag. Both becoming allowed clears it.
  - Later launches (including login) only badge the icon.
- Re-check permissions on capture.onStopped, so a revocation shows at once.
1. 13. Launch at login: LoginItem.swift.
- Uses SMAppService.mainApp. The toggle is on when status == .enabled.
- On: try register(). Off: try unregister().
- .requiresApproval shows the approval hint and a button calling SMAppService.openSystemSettingsLoginItems().
- .notFound disables the toggle with 'Available when Sill runs from its app bundle'.
- Errors show inline, never as alerts.
- Off by default; never switched on automatically.
- Status is re-read on menu open and when a pane appears, never cached.
- It records the bundle's current path, so the script installs to a single location.
1. 14. Log window: LogWindow.swift.
- 'Sill Log', 900×520 with an autosaved frame. An NSScrollView + NSTextView: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular), not editable, selectable, usesFindBar = true, isIncrementalSearchingEnabled = true. Timestamps dimmed.
- On open: load HostLog.shared.lines(after: clearedAt), then set onAppend to append new lines in one batch per 100 ms.
- Keeps at most 5,000 lines, trimming from the top. Stays pinned to the bottom only if it already was.
- Bottom bar:
  - 'Show per-second stats' checkbox: hides lines starting '[1s]', '[30s]' or 'client '.
  - 'Clear': clears the view only.
  - 'Reveal Log File': NSWorkspace.shared.activateFileViewerSelecting.
- Closing sets onAppend = nil.
1. 15. Quit semantics.
- 'Quit Sill' ⌘Q, logout and 'Quit & Reopen' all arrive as NSApp.terminate from the event loop.
- applicationShouldTerminate, first call:
  - coordinator.prepareForQuit(): shuttingDown = true; server.stopAdvertising(), so devices drop the Mac at once.
  - If no staged window is full screen: shutdownForExit() (window home, display removed, synchronous as on signals) and return .terminateNow.
  - Only when a staged window is full screen: return .terminateLater. Call WindowSizer.perform(.fullScreen, element:), then poll with a Timer on RunLoop.main in .common modes every 100 ms, for up to 2 s. Then shutdownForExit() and NSApp.reply(toApplicationShouldTerminate: true).
  - Use a run-loop Timer, not Task.sleep: verified, a Task-based reply never runs if terminate came from a Task.
  - A global-queue watchdog calls exit(0) after 4 s; the atexit VirtualStage.emergencyRestore still puts the window back.
- A second terminate returns .terminateNow.
- No confirmation dialog.
- Signals keep HostShutdown.begin as today (synchronous, 3 s watchdog). Never route them to NSApp.terminate.
- The Info.plist must not opt into sudden or automatic termination.
1. 16. Test hooks, read from the UserDefaults argument domain like the iOS -SillLayout harness:
- -SillLogFile <path>
- -SillQuitAfter <s>: calls NSApp.terminate from a run-loop Timer.
- -SillSetAfter "<s> <key>=<value>[,…]": mutates HostSettings exactly as a control would.
- -SillRenderPreviews <dir>: renders via NSHostingView.cacheDisplay, which is verified to need no Screen Recording, then exits. Outputs: the four panes in light and dark, the status card for canned snapshots, the glyph states, and menu.txt (the menu for those snapshots as text).
- List these next to the iOS harness arguments in CLAUDE.md.
1. 17. What the bundle needs (the build design owns the script):
- Info.plist:
  - CFBundleIdentifier (step 1); CFBundleName and CFBundleDisplayName 'Sill'; CFBundleExecutable 'Sill'; CFBundlePackageType APPL; CFBundleShortVersionString and CFBundleVersion.
  - LSMinimumSystemVersion 14.0; LSUIElement true; LSApplicationCategoryType public.app-category.utilities.
  - An icon made from design/AppIcon.svg (users see it in Privacy & Security and Login Items).
  - NSLocalNetworkUsageDescription 'Sill makes this Mac visible to your iPhone and iPad on the same network so they can stream its windows.'
  - NSBonjourServices [_sill._tcp].
  - No NSSupportsSuddenTermination or NSSupportsAutomaticTermination.
- No sandbox; hardened runtime.
- Sign the whole bundle with the Apple Development identity.
- Install to ~/Applications/Sill.app.
- CLAUDE.md: layout (SillHostKit, SillHost, SillApp), knobs now in HostConfig.standard, how to build, run and find the app's log, the app's debug arguments, and the Current step.

Files: Package.swift: add library SillHostKit; SillHost CLI (main.swift only); app target SillApp → product Sill (layout (a)), Sources/SillHost/*.swift except main.swift: move to Sources/SillHostKit/ (git mv), with `package` on the API the shells call, Sources/VirtualDisplayProbe/VirtualDisplay.swift: repoint the symlink to ../SillHostKit/VirtualDisplay.swift, Sources/SillHost/main.swift: HostConfig.standard plus the flag; everything else unchanged, Sources/SillHostKit/HostConfig.swift (new), Sources/SillHostKit/HostLog.swift (new): ring, file sink, module print shadow, Sources/SillHostKit/HostStatus.swift (new): HostStatusSnapshot, StreamInfo, ClientSummary, Sources/SillHostKit/StreamCoordinator.swift: config, apply, pendingConfig and commit inside select; appKitLoop; enableVirtualDisplay; start options; streamInfo, lastStageFailure, onStatusChanged, statusSnapshot; prepareForQuit, Sources/SillHostKit/StreamServer.swift: per-client stats and clientSummaries; registered name and port; state and failure handler with app retry (CLI exit(1) kept); stopAdvertising; keep the new advertise parameter, Sources/SillHostKit/Stats.swift: lastSecond, Sources/SillHostKit/InputInjector.swift: launchingAppName() returns 'Sill' when running from a bundle (today it names launchd), Sources/SillHostKit/HostShutdown.swift: doc comment (always installed in the app), Sources/SillApp/main.swift (new), Sources/SillApp/AppDelegate.swift (new), Sources/SillApp/MainMenu.swift (new), Sources/SillApp/HostSettings.swift (new), Sources/SillApp/StatusItemController.swift (new), Sources/SillApp/StatusCard.swift (new), Sources/SillApp/StatusText.swift (new), Sources/SillApp/StatusGlyph.swift (new, ported from $SP/glyph/glyph.swift), Sources/SillApp/SettingsWindow.swift (new), Sources/SillApp/SettingsPanes.swift (new), Sources/SillApp/Permissions.swift (new), Sources/SillApp/LoginItem.swift (new), Sources/SillApp/LogWindow.swift (new), Sources/SillApp/DebugHooks.swift (new), Info.plist, Scripts/make-app.sh, app icon (owned by the build design; step 17 lists what the UX needs), CLAUDE.md: layout, knobs location, app build/run/log, debug arguments

Risks:
- App Nap. Nothing holds an activity today. The CLI is never napped, but a windowless LSUIElement app can be. Napping would coalesce the 30 ms keepalive ticks (StreamServer.swift:45-79) and lower the pipeline's priority, which could bring back the 2026-09-22 stutter. Holding .userInitiated + .latencyCritical while a device is connected should prevent it; Noah must measure.
- Main-actor starvation (verified). A menu popUp, runModal, or terminate with .terminateLater started from a Task or main-queue block stops input, client messages, source switches and Stats until it ends. Enforced by the step 7 rule and inline errors.
- Quit deadlock (verified). A Task-based terminateLater reply hangs if terminate came from a Task. Covered by the synchronous fast path, the run-loop-timer wait, the 4 s watchdog, and signals never rerouted to NSApp.terminate.
- Live virtual display toggle. The stage must be released inside the switch before the flag flips, and the catalog refreshed before the window lookup. Otherwise a window stays on the virtual display, input maps to the wrong rectangle, or the stream stops (guard at :417). Untested with permissions.
- In regular mode the app trusts NSWorkspace.frontmostApplication (appKitLoop = true). The CLI's default path never did (:595-597). Believed correct with a live AppKit loop but untested; it decides where clicks and keys from the device go.
- This deviates from the computed task: an AppKit Settings window instead of the SwiftUI Settings scene. The claim that the scene can't be opened from an AppKit menu on macOS 14+ was not re-tested on 27. The scene alternative is MenuBarExtra(.menu), which has no open/close hooks and adds a second lifecycle.
- Permissions. Grants attach to the bundle id plus the designated requirement: ad-hoc rebuilds lose them, and Terminal's grants don't carry over. Screen Recording needs a relaunch, and macOS 15+ re-asks periodically. The first SCShareableContent call raises the system alert, hence the readWindows gating at startup.
- The System Settings deep links (Privacy_ScreenCapture, Privacy_Accessibility, com.apple.Sharing-Settings.extension) are unverified on macOS 27. Fall back to the Privacy & Security root.
- Local Network privacy (macOS 15+) for a LaunchServices-launched app is unknown: advertising or accepting connections may prompt or be blocked. If the iPad can't see the app, check this first.
- Recovering the listener in the app (a new NWListener while old connections live) is untested. The CLI keeps exit(1).
- Running the app and the CLI at once: Bonjour renames one of them, and both would create the same 'Sill' virtual display identity (VirtualStage.swift:124); the outcome is undefined. The menu shows the registered name; optionally warn when a SillHost process is running.
- macOS 26+ menu bar settings, or notch overflow, can hide the status item. Reopening the app shows Settings.
- SMAppService records the bundle path and depends on the signature. Install to one path; ad-hoc behaviour is untested.
- The log holds window titles, device names and IPs in ~/Library/Logs/Sill (rotated at 10 MB). Consider redaction before M6, since users may paste logs into public issues.
- The print shadow is implicit: each module needs its own copy, and Swift.print bypasses it.
- NSMenuItem.subtitle needs macOS 14.4 (verified), so it is guarded with a toolTip fallback.
- A restarting change costs a visible freeze and a keyframe. Under the virtual display, a frame-rate change also recreates the display.
- Unrelated: CLAUDE.md says the periodic keyframe interval is 30 s, but HEVCEncoder.swift:83 sets 4 s. Also, main.swift:63 still prints 'Advertising _sill._tcp' in synthetic mode, which no longer advertises (concurrent edit).

Test plan:
- [No permissions] Baseline first, before any edit. `swift build -c release`, then run `.build/release/SillHost --synthetic > $SP/base-cli.log 2>&1 &` and note the PID. Find the port with `lsof -nP -iTCP -sTCP:LISTEN -a -p PID` and run `python3 $SP/sillclient.py PORT 5 desktop`; expect ≥50 fps. Then `kill PID`.
- [No permissions] Build gate. `swift build -c release 2>&1 | grep -E "error|warning:|Build complete"` shows 0 errors and only the existing CaptureProbe/main.swift:36 warning, for all three products.
- [No permissions] CLI regression. Repeat the baseline run with the new build. Diff line shapes against base-cli.log with digits masked (`sed -E 's/[0-9]+/N/g'`). Expect identical startup lines and 'Streaming…' line, and unprefixed '[1s]' lines. There must be no timestamps, no 'Status:' lines, and no ~/Library/Logs/Sill created by the CLI.
- [No permissions] CLI flags:
- --encoder-selftest exits 0.
- --virtual-display --synthetic starts on the AppKit path; kill -INT prints 'Shutting down…' and exits 130.
- `SillHost --synthetic Safari` starts cleanly.
- --virtual-display-selftest terminates on its own.
- [No permissions] Bundle check:
- `plutil -lint` on the Info.plist passes.
- `defaults read <app>/Contents/Info LSUIElement` returns 1.
- `codesign --verify --strict --verbose=2` passes.
- `codesign -d -r-` shows an identifier plus a certificate requirement, not a bare cdhash.
- No sudden or automatic termination keys.
- [No permissions] App synthetic run. Run the binary directly: `Sill.app/Contents/MacOS/Sill --synthetic -SillLogFile $SP/app.log &`. Find the port with lsof (synthetic mode doesn't advertise) and run sillclient for 5 s; expect ≥50 fps. app.log should have timestamped lines, 'Status: Test Pattern Mode…', the 'Streaming…' line and '[1s]' lines. No Settings window opens. kill -TERM exits 143 after 'Shutting down…'.
- [No permissions] Settings via arguments. Add `-maxFPS 60 -bitrate 8000000 -captureScale 1`. Expect 'Streaming a synthetic test pattern at 1512×948, 60 fps, 8 Mbps'.
- [No permissions] Live apply. Run with `-SillSetAfter "2 maxFPS=60"` and `sillclient.py PORT 6 desktop --fps=120`. Expect a 120 fps stream, then 'Settings: frame rate limit 120 → 60 fps; restarting…', then 60 fps, with frames continuing throughout. Then check:
- bitrate=30000000 restarts the stream.
- virtualDisplay=true while the Desktop streams does not restart.
- maxFPS=120 with only a 60 fps client does not restart.
- [No permissions] Quit and persistence:
- `-SillQuitAfter 3` exits 0 with the 'Quit' log line and no watchdog line; a connected client sees EOF.
- `-SillSetAfter "1 bitrate=30000000" -SillQuitAfter 2`, then relaunch without arguments: the stream starts at 30 Mbps.
- Afterwards, `defaults delete me.saffer.sill.mac`.
- [No permissions] Previews. `-SillRenderPreviews $SP/previews`, then read the PNGs and menu.txt. Check:
- the four panes in light and dark;
- status cards for idle, connected, streaming, two devices, software encoder, permissions missing and not advertised;
- glyph states;
- copy against steps 10-11, and no clipping at 520 pt.
- [No permissions] Cleanup gate. `pgrep -fl "SillHost|Sill.app/Contents/MacOS/Sill"` lists none of the test's PIDs. The iOS Simulator's Sill.app is Noah's; leave it running.
- [Noah] Install to ~/Applications and open it from Finder. The status item appears, with no Dock icon and no ⌘-Tab entry. Settings opens on Permissions. Note whether a Local Network prompt appears.
- [Noah] Screen Recording: Allow…, then the system alert, then enable Sill in System Settings, then Quit & Reopen or Relaunch Sill; the pane shows Allowed. Accessibility flips live. Both Privacy lists show Sill with its icon. The deep links open the right panes.
- [Noah] Rebuild and reinstall, then relaunch. Both grants still hold (Apple Development signature).
- [Noah] Stream from the iPad with the menu open for 10 s. The card's fps, frame age and RTT update live, and taps and typing from the iPad keep working while the menu is open.
- [Noah] Change frame rate (a ProMotion iPad: 120 vs 60), quality and resolution while streaming. Each causes one short freeze, then the stream recovers. The Log window shows 'Settings:' lines.
- [Noah] Virtual display while a window streams. On: the window leaves the Mac screen and keeps streaming. Off: it returns to its exact original frame. Clicks and typing land correctly after each toggle. Repeat with the window in full screen.
- [Noah] With another app frontmost on the Mac, tap into the streamed window from the device. The app activates and the click lands. Compare with `swift run -c release SillHost`.
- [Noah] Latency and App Nap. Compare -SillHUD frame age and RTT for the app vs the CLI, 5 min each, including 10 min with no Mac input. `pmset -g assertions | grep -i sill` shows the activity only while a device is connected. Idle CPU is 0.0 % with the menu closed.
- [Noah] Quit with a staged window, normal and full screen. The window goes back home, no Sill display remains in System Settings › Displays, and the process is gone in ≤4 s. Logging out while streaming does not interrupt the logout.
- [Noah] Launch at login: toggle on and check Login Items. Log out and in: Sill starts with no windows. Toggle off removes it.
- [Noah] Hide the status item, then double-click Sill.app: Settings opens.
- [Noah] Run the CLI while the app runs. The menu shows the name Bonjour registered with ' (2)'. Keep the virtual display on in only one of them.
- [Noah] Revoke Screen Recording while streaming. The stream stops, the glyph shows attention, and the header reads 'Screen Recording Is Off'.
- [Noah] Log window while streaming: live lines, ⌘F, ⌘C, the stats toggle and Reveal Log File all work.

### Design 2: Sill.app menu-bar host, built with SwiftPM only: a host library, two executables and a script that wraps and signs the bundle

Decision: (a), SwiftPM only. One `swift build -c release` compiles three things: the host library, the SillHost CLI (unchanged for the user) and the SillMenuBar app. `Scripts/make-app.sh` (about 110 lines of bash) wraps SillMenuBar into Sill.app with a checked-in Packaging/Info.plist, compiles the icon with Xcode's own actool, and signs the bundle with the Apple Development identity from the keychain. A draft of the script was run end to end in the scratchpad. Clean build about 16 s, incremental about 2 s.

How the two options compare:
- **Reproducibility.** (a) is one build system that Claude sessions and CI can drive headless, and the bundle layout is readable in the script. (b) means a hand-written pbxproj, and `swift build` would never compile the Xcode app shell, so a change to the library API could break it unnoticed.
- **Signing.** Both end in the same `codesign` call. Signing with "Apple Development: … (HG877AGTQ7)", team 9B2KKVM937, ran without a keychain prompt here. `--release` switches to Developer ID with hardened runtime and a timestamp.
- **Permissions attribution.** Identical in both: TCC keys on the bundle ID plus the designated requirement.
- **Icon.** Now equal. actool compiles a generated Icon Composer document from design/AppIcon.svg into Assets.car plus a pre-masked .icns. A sips/iconutil .icns was shrunk into a grey tile on macOS 27; the actool output renders natively.
- **How Noah works.** He runs the host from Terminal, and Claude sessions build it. He can still open Package.swift in Xcode for editing and use Attach to Process (dev builds carry get-task-allow).
- **What would flip it to (b).** M5 CloudKit pairing needs iCloud entitlements, which need a provisioning profile. Xcode's automatic signing manages that; the script would have to embed `embedded.provisionprofile` by hand. The library split and public API are the same work under (a) and (b), so moving an app target into an Xcode project later is cheap.

**Layout (one file move).**
- The library target `SillHostCore` keeps its 16 files in Sources/SillHost via `path:`. The working tree carries uncommitted edits, and another session changed StreamServer.swift (`advertise: !synthetic`) during this design; leaving the files in place avoids path churn. The VirtualDisplayProbe symlink stays valid.
- Only main.swift moves, to Sources/SillHostCLI.
- The product keeps the name `SillHost`, so `swift run -c release SillHost …` and .build/release/SillHost do not change.

**Runtime.**
- An `@Observable` main-actor `HostSettings` replaces the four knob `let`s. The CLI builds one from its constants; the app loads and saves it in UserDefaults.
- The coordinator copies the settings at the start of every `select`, so one pipeline never mixes two values. Virtual-display mode changes only inside `select`. A change restarts the current source, the same restart a device's rate change already causes, and a change that arrives mid-switch waits and is re-checked afterwards.
- `HostStatus`, also `@Observable`, is pushed by events (listener, Bonjour name, devices and their stats, the stream, fallbacks). Nothing polls, so an idle host stays idle.
- A module-level `print` in SillHostCore shadows Swift.print for all 92 call sites without editing them. Each line goes to stdout (the CLI's output is unchanged), to a 5000-line ring buffer for the Log window, and in the app to the unified log.
- The app is a SwiftUI `MenuBarExtra(.menu)` with a `Settings` scene and a `Window("Sill Log")` scene, LSUIElement set. HostShutdown is always installed, and Quit calls a new `releaseForQuit`.

**How TCC grants survive rebuilds.**
- A grant is stored as the bundle ID plus a snapshot of the code's designated requirement, and every access is checked against that snapshot.
- The Apple Development requirement names the bundle ID and the certificate CN, not the binary: `identifier "me.saffer.sill.mac" and anchor apple generic and certificate leaf[subject.CN] = "Apple Development: … (HG877AGTQ7)" and certificate 1[field.1.2.840.113635.100.6.2.1] exists`. It also survives certificate renewal, since the CN stays the same; the current certificate is valid to 2027-09-22.
- Verified: a rebuilt, re-signed bundle passes `codesign --verify -R=<requirement recorded before the rebuild>`.
- An ad-hoc requirement is a cdhash; the rebuilt ad-hoc bundle failed its old requirement. The toggle stays on in System Settings but access is denied.
- Rules for Noah:
  - Always sign with the same identity, and sign last.
  - Keep one installed copy, /Applications/Sill.app, and launch it from Finder, `open` or the login item. Running Contents/MacOS/Sill from Terminal makes Terminal the responsible process.
  - Moving to Developer ID gives a team-based requirement, which means granting once more.
  - If grants go stale: `tccutil reset ScreenCapture me.saffer.sill.mac` and `tccutil reset Accessibility me.saffer.sill.mac`.
  - The CLI keeps using Terminal's grants.

**Prototype.** Everything above was prototyped in the scratchpad under d1proto (full path /private/tmp/claude-501/-Users-noah-Downloads-winstream/8c347207-ca84-4178-90e4-157cc440b6d8/scratchpad/d1proto):
- `repo2`: the one-file-move layout, all core edits, a minimal app shell, Scripts/ and Packaging/.
- `edit_core.py`: the exact edit pairs.
- `out/*.log`: evidence logs.
- `iconcheck/*.png`: icon renders.
- `glyph1/`: the status glyph.

Results:
- Build: 0 errors. The only warning is the existing one at Sources/CaptureProbe/main.swift:36.
- CLI `--synthetic` output matches the baseline, lines sorted and numbers folded. The installed-apps line lands wherever its background scan finishes, as it does today.
- The `--virtual-display` flag path still exits 130 on Ctrl-C with "Shutting down…".
- The app binary streamed the synthetic pattern at 60 fps. It honoured `-maxFPS 60 -bitrate 25000000` from the argument domain, and after live changes (bitrate; virtual display on; scale, fps and encoder speed together) it restarted three times; the last three changes coalesced into one restart.
- SIGTERM exits 143 through HostShutdown.

Side effect to report: during the first baseline run (about 02:58), Noah's iPad (iPad14,1) joined the synthetic host over AWDL and showed the test pattern. That is probably part of the "white moving wall"; the `advertise: !synthetic` change that has since landed prevents it.

Steps:
1. 0. Before editing anything:
- Capture the CLI baseline with the ground-rule recipe: `.build/release/SillHost --synthetic` to a scratch log, find the port with lsof, run `sillclient.py PORT 5 desktop`, kill the host by PID.
- The tree has uncommitted edits in CLAUDE.md, Sources/SillHost/StreamCoordinator.swift and Sources/SillHost/StreamServer.swift (`advertise: !synthetic`). Never stash, checkout or overwrite them.
- Re-read each file just before editing it: another session edited StreamServer.swift during this design.
1. 1. Split the package, moving one file.
- `git mv Sources/SillHost/main.swift Sources/SillHostCLI/main.swift`, then add `import SillHostCore` to it.
- Package.swift products: `.library(name: "StreamProtocol", …)`, `.executable(name: "SillHost", targets: ["SillHostCLI"])`, `.executable(name: "SillMenuBar", targets: ["SillMenuBar"])`.
- Package.swift targets:
  - `.target(name: "StreamProtocol")`
  - `.target(name: "SillHostCore", dependencies: ["StreamProtocol"], path: "Sources/SillHost")`
  - `.executableTarget(name: "SillHostCLI", dependencies: ["SillHostCore", "StreamProtocol"])`
  - `.executableTarget(name: "SillMenuBar", dependencies: ["SillHostCore", "StreamProtocol"])`
  - CaptureProbe and VirtualDisplayProbe unchanged.
- Give SillHostCore no library product, so the iOS project never sees it.
- Keep tools 5.9 (Swift 5 mode). Comment why the folder name and module name differ.
- Verified: the `SillHost` product still builds `.build/release/SillHost`, and `swift run -c release SillHost --encoder-selftest` works.
1. 2. Make public only what the shell calls. When main.swift moved out, the compiler named exactly these: StreamCoordinator, Stats, HostShutdown, EncoderSelfTest, VirtualDisplaySelfTest.
- `public final class StreamCoordinator` with:
  - `public init(settings: HostSettings, status: HostStatus? = nil, synthetic: Bool = false, appKitLoop: Bool) throws`. `status` is optional because a main-actor default argument does not compile.
  - `public let settings`, `public let status`, `public var onFatalError: ((String) -> Void)?`
  - `public private(set) var active`, `public var windowCount: Int { catalog.infos.count }`
  - `public func start(preselect:) async`, `public func shutdownForExit()`
- `public final class Stats` with `public static let shared` and `public func startPrinting()`.
- `public enum HostShutdown` with `install` public.
- `public static func run()` on both self-tests.
1. 3. New Sources/SillHost/HostLog.swift.
- A module-internal `func print(_ items: Any..., separator: String = " ", terminator: String = "\n")` shadows Swift.print inside SillHostCore only. All 92 call sites stay untouched; map 1 counted 94 because it matched `fingerprint(` twice.
- Each line goes through `HostLog.write`, which does three things:
  - `Swift.print(line, terminator:)` when echo is on.
  - `Logger(subsystem: bundleID, category: "host").notice(…, privacy: .public)` when configured.
  - Appends to the ring buffer.
- Public API: `HostLog.configure(echoToStdout:keepLines:unifiedLogSubsystem:)` (call once, before the host starts), `HostLog.buffer`, `HostLog.line(_:)` for the app shell's own lines.
- Defaults are echo on, keep 0, no unified log, so the CLI prints exactly as today.
- `LogBuffer`, guarded by an NSLock:
  - A ring of `Line(seq, date, text)`, with `lines(after:)` and `clear()`.
  - `onAppend` wakes the main queue at most once at a time, and never while no one reads.
1. 4. New Sources/SillHost/HostSettings.swift: `@MainActor @Observable public final class HostSettings`.
- Properties: `virtualDisplay`, `maxFPS`, `scale`, `bitrate`, `prioritizeSpeed`. Each has `didSet { if value != oldValue { changed() } }`.
- Hook: `@ObservationIgnored public var onChange`.
- `init(maxFPS:scale:bitrate:prioritizeSpeed:virtualDisplay:)` is the CLI's; it is never persisted.
- `init(defaults: UserDefaults)` is the app's. It `register`s today's CLI values (120, 2.0, 15_000_000, false, false) and clamps what it loads: fps 24…120, scale 1 or 2, bitrate 1–100 Mbps.
- `changed()` writes the keys maxFPS, captureScale, bitrate, prioritizeSpeed and virtualDisplay, then calls onChange.
- `public enum Quality: Int`: efficient 8M, balanced 15M (today's value), high 25M, maximum 40M, all per 60 fps.
- The argument domain overrides without writing anything: `-maxFPS 60` was verified.
1. 5. In StreamCoordinator, turn the knobs into settings that stay fixed for each pipeline.
- Delete `let maxFPS` (line 14) and `let scale`, `let bitrate`, `let prioritizeSpeed` (28–30).
- Add `private var runScale`, `runBitrate`, `runPrioritizeSpeed` and `private let appKitLoop`.
- Point the reads at them:
  - `wantedFPS` (22) reads `settings.maxFPS`.
  - `streamBitrate` (27) becomes `runBitrate * fps / 60`.
  - `captureScale` (731) uses `runScale`.
  - `HEVCEncoder(… prioritizeSpeed: runPrioritizeSpeed)` (501).
- In `select`, right after `fps = effectiveFPS` (386), add `runScale = settings.scale; runBitrate = settings.bitrate; runPrioritizeSpeed = settings.prioritizeSpeed; await adoptVirtualDisplaySetting()`.
- `let virtualDisplay` (42) becomes `private(set) var virtualDisplay`. The name stays, so its 20-odd reads keep their meaning: the mode the running pipeline uses.
- `adoptVirtualDisplaySetting()`:
  - Turning off: first `await stage.leaveFullScreenIfNeeded(); stage.release()`.
  - Then set `virtualDisplay`, set `catalog.preferMainDisplay`, and log `Virtual display on/off (settings).`
  - Turning on: call `checkVirtualDisplayAPI()`. That is the start-time block at 177–187 moved into a run-once function with the same print; `start()` still calls it under the mode, so the CLI's output order is unchanged.
- `activePID(trustAppKit:)` at 605 and 630 gets `appKitLoop`. The CLI passes its --virtual-display flag, so nothing changes there; the app passes true.
1. 6. Apply changes live.
- In init: `settings.onChange = { [weak self] in Task { @MainActor in await self?.settingsChanged() } }`.
- `settingsChanged()`:
  - If shutting down: return.
  - If `switching`: set `settingsChangedWhileSwitching = true` and return.
  - If `active == .none`: `await select(.none)` only when the mode differs.
  - Otherwise `await select(active)` when any of these holds: `effectiveFPS != fps`, scale, bitrate or speed differ from the run values, or the source is `.window` and the mode differs. The Desktop picks up a mode change at its next select.
- In select's `defer`, after the viewport block: if the flag is set, clear it and `Task { @MainActor in await self.settingsChanged() }`.
- Prototype result: bitrate change, then virtual display on, then scale + fps + speed together gave exactly three restarts; the device kept about 60 fps.
1. 7. New Sources/SillHost/HostStatus.swift, plus wiring.
- `@MainActor @Observable public final class HostStatus`, every property `public internal(set)`:
  - `advertisedName: String?`, `advertises: Bool`
  - `listener`: `.starting`, `.ready`, `.waiting(String)` or `.failed(String)`
  - `devices: [Device]`, each with id, endpoint, and name/fps/frameAgeMs/rttMs from ClientStats
  - `stream: Stream?` (title, size, fps, Mbps, softwareEncoder, onVirtualDisplay)
  - `encodedFPS`, `softwareEncoderFallback`, `virtualDisplayProblem`
- New StreamServer callbacks:
  - `onListenerState`.
  - `onServiceRegistered`, set through `listener.serviceRegistrationUpdateHandler`; `.add(.service(name,…))` gives the name after a Bonjour rename.
  - `onClientStats`: decode every report; keep printing every 1.5 s as at lines 180–182.
- Coordinator:
  - Append a device in onClientConnected; remove it in onClientDisconnected.
  - Set `status.stream` in startPipeline next to the `Streaming …` print. Add a `title:` parameter: "App — Window", "Desktop" or "Test pattern".
  - Clear it in `active`'s didSet on `.none`.
  - Set the software-encoder fallback flag at 173 and 759, and `virtualDisplayProblem` wherever `stage.disabledReason` is set.
- Stats gets an internal `onTick` called from tick() on the main queue. The coordinator applies it with `Task { @MainActor … }`. Do not use `MainActor.assumeIsolated`: under the CLI's dispatchMain() the main queue runs on a worker thread, and the prototype trapped there.
1. 8. Exits and shutdown.
- StreamServer (101–103): keep printing `Listener failed: …`, then call `onListenerState`. Remove exit(1) from the library. The coordinator passes `.failed` to `onFatalError` right away, on the network queue.
- HostShutdown: add `@MainActor public static func releaseForQuit(coordinator:)`. Same `began` guard, same message, same 3 s watchdog that calls `exit(0)`, then `coordinator?.shutdownForExit()`. It does not exit; AppKit does.
- InputInjector.ensureAccessibility, launchingAppName and the 30 s reminder (425–460): when `Bundle.main.bundleIdentifier != nil && getppid() == 1` (a LaunchServices launch; ppid 1 was measured), name "Sill" and say "quit and reopen Sill". Otherwise keep today's Terminal text.
1. 9. Sources/SillHostCLI/main.swift.
- The knobs stay as `let`s.
- In startHost:
  - `let settings = HostSettings(maxFPS: maxFPS, scale: scale, bitrate: bitrate, prioritizeSpeed: prioritizeSpeed, virtualDisplay: virtualDisplay)`
  - `let c = try StreamCoordinator(settings: settings, synthetic: synthetic, appKitLoop: virtualDisplay)`
  - `c.onFatalError = { _ in exit(1) }`, set before `start`.
  - Use `c.windowCount` in the count line.
- Flags, self-tests, the preselect argument, HostShutdown under the flag, `NSApplication` with `.prohibited`, and `dispatchMain()` are all unchanged.
1. 10. New app target, Sources/SillMenuBar/SillApp.swift + AppDelegate.swift + AppModel.swift.
- `@main struct SillApp: App` with `@NSApplicationDelegateAdaptor`. Scenes, in this order:
  - `MenuBarExtra { MenuContent } label: { StatusLabel }.menuBarExtraStyle(.menu)`
  - `Settings { SettingsView }`
  - `Window("Sill Log", id: "log") { LogView }.defaultSize(width: 760, height: 460)`
  - Verified: only the status item exists at launch.
- `applicationDidFinishLaunching`, in this order:
  - `HostLog.configure(echoToStdout: true, keepLines: 5000, unifiedLogSubsystem: Bundle.main.bundleIdentifier)`
  - `setvbuf(stdout, nil, _IOLBF, 0)`; `signal(SIGPIPE, SIG_IGN)`
  - `ProcessInfo.processInfo.disableAutomaticTermination(…)` and `disableSuddenTermination()`
  - `NSApp.setActivationPolicy(.accessory)`, for runs of the bare binary
  - `_ = CGMainDisplayID()`
  - `HostShutdown.install { model.coordinator }`, always, so kill and pkill also put windows back
  - `model.start()`
- `model.start()` creates `StreamCoordinator(settings: HostSettings(defaults: .standard), status: model.status, synthetic: CommandLine.arguments.contains("--synthetic"), appKitLoop: true)`, awaits `start(preselect: nil)`, calls `Stats.shared.startPrinting()`, and records errors in `model.startupError`.
- `applicationShouldTerminate`: `HostShutdown.releaseForQuit(coordinator:)`, then `.terminateNow`. This covers Quit, logout and Screen Recording's Quit & Reopen.
- `applicationShouldHandleReopen` opens Settings, using the `openSettings` action captured in StatusLabel's onAppear. Verified: the label is alive from launch; menu content is not built until the menu opens. This matters when a notch hides the status item.
1. 11. MenuContent.swift and StatusGlyph.swift.
- Status block, as disabled items:
  - `Advertising as “<name>”`, `Starting…`, `Not visible to devices: <reason>`, or `Test mode: not advertised`.
  - One row per device, e.g. `iPad (iPad14,1) — 60 fps · 9 ms · rtt 7 ms`, or `No devices connected`.
  - `Streaming Safari — Apple · 60 fps · 3024×1898`, with `· virtual display` or `· software encoder` when true, or `Nothing streaming`.
  - A button per missing permission: `Screen Recording is off — Grant…`.
- Controls:
  - `Toggle("Virtual Display")`
  - `Picker("Frame Rate Limit")`: 60 / 120
  - `Picker("Quality")` over `HostSettings.Quality`
  - `Picker("Capture")`: Retina (2×) / Points (1×)
  - `Menu("Permissions")`, `Toggle("Launch at Login")`
  - `Show Log…`: `openWindow(id:"log")` + `NSApp.activate()`
  - `Settings…` ⌘,: `openSettings()` + `NSApp.activate()`
  - `Quit Sill` ⌘Q: `NSApp.terminate(nil)`
- Views take `@Bindable var settings: HostSettings` directly; a `$model.settings.x` binding does not compile.
- Refresh permissions on `NSMenu.didBeginTrackingNotification` and `NSApplication.didBecomeActiveNotification`.
- StatusGlyph: a code-drawn 20×16 pt template image (`isTemplate = true`): the iMac with its stand and the tilted iPad in front. Streaming fills the iPad screen; a missing permission or failed listener adds a `!` badge. Prototype: glyph1/glyph.swift and glyph-sheet.png.
1. 12. SettingsView.swift, Permissions.swift, LoginItem.swift, LogView.swift.
- SettingsView: a `TabView` of `Form { }.formStyle(.grouped)` tabs, about 480 pt wide.
  - General: login item with its approval state; `Running from <path>` with a warning when it is outside /Applications; advertised name; devices; encode fps; Show Log…; Quit Sill.
  - Streaming: the four controls plus `Favor encoding speed over quality` for prioritizeSpeed, and the note "Changes restart the current stream: a brief black frame on the device".
  - Permissions: a row per permission with status and a button, a Local Network hint, and Relaunch Sill.
- Permissions calls:
  - Status: `CGPreflightScreenCaptureAccess()` and `AXIsProcessTrusted()`.
  - Request: `CGRequestScreenCaptureAccess()` and `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)`.
  - Open System Settings: `NSWorkspace.shared.open` with `x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture` or `?Privacy_Accessibility`.
  - Poll once a second only while the tab is visible (`.task`).
  - Relaunch: run `/bin/sh -c 'sleep 1; /usr/bin/open "$0"' <bundlePath>` as a `Process`, then terminate.
- LoginItem:
  - Read `SMAppService.mainApp.status`. Treat `.notRegistered` and `.notFound` as off; a never-registered app reported `.notFound` here.
  - `try SMAppService.mainApp.register()` and `try await …unregister()`.
  - `.requiresApproval` shows a button calling `SMAppService.openSystemSettingsLoginItems()`.
  - The system is the source of truth; nothing goes into UserDefaults.
- LogView: an NSViewRepresentable around `NSTextView.scrollableTextView()`.
  - Read-only, selectable, monospaced 11 pt, `usesFindBar = true`.
  - Loads `HostLog.buffer.lines(after: 0)`, sets `onAppend` on appear and clears it on disappear.
  - Appends lines as `HH:mm:ss.SSS  text` and follows the tail only when already scrolled to the bottom.
  - Buttons: Copy All, Save… (NSSavePanel), Clear.
1. 13. Packaging/Info.plist (checked in).
- CFBundleIdentifier `me.saffer.sill.mac`. Noah confirms it before the first grant: TCC, Login Items, defaults and M5 iCloud all key off it.
- CFBundleName and CFBundleDisplayName Sill; CFBundleExecutable Sill; APPL; CFBundleShortVersionString 0.3.0. The script sets CFBundleVersion from `git rev-list --count HEAD`.
- CFBundleIconFile and CFBundleIconName: AppIcon.
- LSMinimumSystemVersion 14.0; LSUIElement true; LSApplicationCategoryType utilities.
- NSLocalNetworkUsageDescription, and NSBonjourServices `[_sill._tcp]`.
- NSSupportsAutomaticTermination and NSSupportsSuddenTermination false; NSPrincipalClass NSApplication.
- Packaging/SillDebug.entitlements holds only `com.apple.security.get-task-allow`, for lldb and Xcode attach. `sample <pid>` works on the hardened app without it; that was measured.
- No other entitlements: the hardened runtime needs none for ScreenCaptureKit, CGEvent posting, Network, or the private CGVirtualDisplay (which is looked up at runtime).
1. 14. Scripts/make-app.sh (tested draft at d1proto/repo2/Scripts/make-app.sh).
- Build: `swift build -c release --product SillMenuBar`; take the bin path from `--show-bin-path`.
- Assemble in `.build/Sill.app.partial`, sign it, run `codesign --verify --strict`, then `mv` it over `.build/Sill.app`, so a failed run never leaves half a bundle.
- Icon:
  - `qlmanage -t -s 1024` renders design/AppIcon.svg full-bleed.
  - Generate a one-layer Icon Composer document: solid black fill, layer `Sill.png`, squares macOS.
  - Compile with `xcrun actool --compile <abs> --platform macosx --minimum-deployment-target 14.0 --app-icon AppIcon --output-partial-info-plist <abs> <abs>/AppIcon.icon`, which gives Assets.car + AppIcon.icns.
  - Use absolute paths only: actool resolved relative ones in a stale directory.
  - Cache the result in .build/icon. A layered Packaging/AppIcon.icon made later in Icon Composer takes precedence.
- Signing:
  - Identity: `$SILL_SIGN_IDENTITY`, else the first `Apple Development:` from `security find-identity -v -p codesigning`, else ad hoc with a loud warning.
  - Dev builds: `codesign --force --options runtime --timestamp=none --entitlements Packaging/SillDebug.entitlements`.
  - `--release`: `--options runtime --timestamp` with no entitlements.
  - Print the designated requirement.
- `--install`:
  - `pkill -TERM -f 'Sill\.app/Contents/MacOS/Sill'`, so HostShutdown puts windows back. Never `pkill -x Sill`: that also matches the iOS Simulator's Sill app, which is running now.
  - Wait up to 5 s, then `rm -rf` and `ditto` into `${SILL_INSTALL_DIR:-/Applications}/Sill.app`.
- `--open`: open the installed copy.
1. 15. Docs.
- README Mac host section: `Scripts/make-app.sh --install --open`, grant Sill (not Terminal), the TCC rules from the approach, reading the log with `/usr/bin/log stream --predicate 'subsystem == "me.saffer.sill.mac"'` (zsh has a `log` builtin), and the M6 notarization commands (`xcrun notarytool submit … --keychain-profile …`, `xcrun stapler staple`). Noah stores the notary credentials himself.
- CLAUDE.md: Layout, Build and run, and a Current step paragraph with the lessons learned here. Keep its uncommitted edits.
- design/README.md: the Mac icon pipeline.
- docs/BRIEF.md stays untouched.
1. 16. Verify with the test plan. Build: `cd /Users/noah/Downloads/winstream && swift build -c release 2>&1 | grep -E "error|warning:|Build complete"` should show 0 errors, and the only warning should be the existing CaptureProbe one (Sources/CaptureProbe/main.swift:36).

Files: /Users/noah/Downloads/winstream/Package.swift, /Users/noah/Downloads/winstream/Sources/SillHost/main.swift (git mv to /Users/noah/Downloads/winstream/Sources/SillHostCLI/main.swift, then edit), /Users/noah/Downloads/winstream/Sources/SillHost/StreamCoordinator.swift, /Users/noah/Downloads/winstream/Sources/SillHost/StreamServer.swift, /Users/noah/Downloads/winstream/Sources/SillHost/Stats.swift, /Users/noah/Downloads/winstream/Sources/SillHost/HostShutdown.swift, /Users/noah/Downloads/winstream/Sources/SillHost/InputInjector.swift, /Users/noah/Downloads/winstream/Sources/SillHost/EncoderSelfTest.swift, /Users/noah/Downloads/winstream/Sources/SillHost/VirtualDisplaySelfTest.swift, /Users/noah/Downloads/winstream/Sources/SillHost/HostLog.swift (new), /Users/noah/Downloads/winstream/Sources/SillHost/HostSettings.swift (new), /Users/noah/Downloads/winstream/Sources/SillHost/HostStatus.swift (new), /Users/noah/Downloads/winstream/Sources/SillMenuBar/SillApp.swift (new), /Users/noah/Downloads/winstream/Sources/SillMenuBar/AppDelegate.swift (new), /Users/noah/Downloads/winstream/Sources/SillMenuBar/AppModel.swift (new), /Users/noah/Downloads/winstream/Sources/SillMenuBar/MenuContent.swift (new), /Users/noah/Downloads/winstream/Sources/SillMenuBar/StatusGlyph.swift (new), /Users/noah/Downloads/winstream/Sources/SillMenuBar/SettingsView.swift (new), /Users/noah/Downloads/winstream/Sources/SillMenuBar/Permissions.swift (new), /Users/noah/Downloads/winstream/Sources/SillMenuBar/LoginItem.swift (new), /Users/noah/Downloads/winstream/Sources/SillMenuBar/LogView.swift (new), /Users/noah/Downloads/winstream/Scripts/make-app.sh (new), /Users/noah/Downloads/winstream/Packaging/Info.plist (new), /Users/noah/Downloads/winstream/Packaging/SillDebug.entitlements (new), /Users/noah/Downloads/winstream/README.md, /Users/noah/Downloads/winstream/CLAUDE.md (keep its uncommitted edits), /Users/noah/Downloads/winstream/design/README.md, Unchanged on purpose: /Users/noah/Downloads/winstream/docs/BRIEF.md, /Users/noah/Downloads/winstream/iOSClient/, /Users/noah/Downloads/winstream/Sources/StreamProtocol/, /Users/noah/Downloads/winstream/Sources/VirtualDisplayProbe/VirtualDisplay.swift (the symlink to ../SillHost/VirtualDisplay.swift stays valid), /Users/noah/Downloads/winstream/.gitignore (all output goes to .build), Reference prototype, scratch only, not to be copied wholesale: /private/tmp/claude-501/-Users-noah-Downloads-winstream/8c347207-ca84-4178-90e4-157cc440b6d8/scratchpad/d1proto/repo2 (layout, core edits, minimal app, Scripts/make-app.sh, Packaging/). Edit pairs: /private/tmp/claude-501/-Users-noah-Downloads-winstream/8c347207-ca84-4178-90e4-157cc440b6d8/scratchpad/d1proto/edit_core.py

Risks:
- Settings and Log windows in an accessory app may open behind other apps. Seen here: without a user click, `NSApp.activate()` was refused under cooperative activation, and both windows opened visible but not key. Called from a menu click it should succeed. Fallback: `orderFrontRegardless()` on the new window. Last resort: `.regular` activation policy while a Sill window is open, but first check that the virtual display still sees its modes under `.regular`; it was only measured under `.accessory` and `.prohibited`.
- Local Network privacy (macOS 15+) applies to the app, not to tools run from Terminal. What exactly triggers the prompt for a listener that also advertises is unverified, and so is whether a rebuild re-prompts. The usage string and NSBonjourServices are in the plist; the menu says 'Not visible to devices' when Bonjour registration never arrives.
- Signing identity changes cost one re-grant. Developer ID has a team-based requirement, so Apple Development grants will not match it. M5 CloudKit needs a provisioning profile, which the script would have to embed by hand; that is the point where (b) Xcode becomes attractive. The library split keeps that move cheap.
- TCC attribution traps:
- Running Sill.app/Contents/MacOS/Sill from Terminal makes Terminal the responsible process.
- With both .build/Sill.app and /Applications/Sill.app registered, LaunchServices may open either.
- The login item records the bundle's path. Keep one installed copy.
- The `print` shadow is implicit. It covers only the SillHostCore module, and an explicit `Swift.print` would bypass the Log window. Document it in HostLog.swift.
- `MainActor.assumeIsolated` traps in the default CLI path: dispatchMain() runs the main queue on a worker thread (seen in the prototype). Any new callback that can run in the CLI must hop with `Task { @MainActor }`. HostShutdown's existing use is safe only because it is installed under the AppKit loop.
- Every settings change restarts the current source: a brief black frame and a keyframe on the device. A change mid-switch is queued and re-checked. A virtual-display change while a window is full screen on it takes up to 2 s (`leaveFullScreenIfNeeded`).
- Behaviour change in the app only: `trustAppKit` is always true, so regular mode reads `NSWorkspace.frontmostApplication` instead of the owner of the topmost window. Untested with Accessibility granted. Reverting is one argument.
- The CLI and the app running at once means two hosts: Bonjour renames one (the menu shows the renamed name), and both could create a virtual display with the same Sill identity. Quit one of them.
- Other sessions edit Sources/SillHost/*.swift concurrently (StreamServer.swift changed during this design). The one-file-move layout avoids path churn, but the implementer must re-read files right before each edit and keep the uncommitted diffs.
- Icon tooling needs Xcode's actool and a Quick Look render. If either fails, the bundle gets the generic icon with a warning. The single generated layer gets default glass highlights; real depth needs a four-layer .icon made in Icon Composer.
- The menu is built when it opens (verified: menu content's onAppear never fired while it was closed). Whether its rows update while it stays open is unverified; at worst they refresh on the next open.
- Screen Recording: macOS 15+ may ask a long-running app to re-confirm periodically; behaviour on 27 is unknown. A grant takes effect only after a relaunch (macOS offers Quit & Reopen). SMAppService reported `.notFound` for a never-registered app here, and the approval flow is untested.
- The bare `.build/release/SillMenuBar` binary uses the UserDefaults domain 'SillMenuBar', not me.saffer.sill.mac, and has no unified-log mirror. Only the bundle reflects real settings and TCC.
- The status item can hide behind the notch on a crowded menu bar (this Mac's menu bar is 33 pt, a notch model). Mitigations: reopening Sill.app opens Settings, and the General tab has a Quit button.

Test plan:
- [no permissions] Build: `cd /Users/noah/Downloads/winstream && swift build -c release 2>&1 | grep -E "error|warning:|Build complete"`. Expect 0 errors and only the existing warning at Sources/CaptureProbe/main.swift:36 (as in the prototype).
- [no permissions] CLI parity: run the ground-rule recipe on the new `.build/release/SillHost --synthetic` and expect about 60 fps from `sillclient.py PORT 5 desktop`. Compare with the baseline taken in step 0: `diff <(grep -v '^\[1s\]' base.log | sed -E 's/[0-9]+/N/g' | sort) <(… new.log …)` should be empty. Sort both, because the 'installed apps' line lands wherever its background scan finishes. Synthetic hosts no longer advertise, so no device joins.
- [no permissions] CLI flag paths:
- `SillHost --synthetic --virtual-display`, then SIGINT: exit 130 with 'Shutting down…'.
- `swift run -c release SillHost --encoder-selftest`: hardware and software sections plus the stats line.
- `SillHost --synthetic Safari` (preselect): the same startup lines.
- Optional: `--virtual-display-selftest` exits 0.
- [no permissions] App binary without a bundle, launched from the shell so Terminal is responsible and nothing prompts: `.build/release/SillMenuBar --synthetic -maxFPS 60 -bitrate 25000000 > app.log`. Get the port with lsof on its PID, run `sillclient.py PORT 5 desktop --fps=120`. Expect about 60 fps and 'Streaming a synthetic test pattern at 3024×1898, 60 fps, 25 Mbps'. `kill -TERM PID` should exit 143 with 'Shutting down…'. A Sill status item shows in the menu bar while it runs. The prototype passed this.
- [no permissions] Idle footprint: run the same binary with no client for 60 s. `ps -o %cpu,rss -p PID` should show about 0.0 % CPU (events push status, nothing polls). Kill it by PID.
- [no permissions] Bundle: `Scripts/make-app.sh`.
- The output says 'signed by: Apple Development: … (HG877AGTQ7)'.
- `codesign --verify --strict --verbose=2 .build/Sill.app` passes.
- `codesign -d -r- .build/Sill.app` shows the identifier + certificate-CN requirement.
- `plutil -p .build/Sill.app/Contents/Info.plist` shows LSUIElement 1 and CFBundleIconName AppIcon.
- Resources contain Assets.car and AppIcon.icns.
- A second run takes about 2 s.
- [no permissions] Proof that TCC grants survive rebuilds:
- `DR=$(codesign -d -r- .build/Sill.app 2>&1 | sed -n 's/^designated => //p')`, edit a comment under Sources/SillMenuBar, rerun the script, then `codesign --verify -R="$DR" .build/Sill.app` must pass.
- Contrast: with `SILL_SIGN_IDENTITY=-`, two builds with a code change in between fail the same check (both shown in the prototype).
- [no permissions] Icon: render .build/Sill.app with d1proto/iconcheck/render (NSWorkspace icon). Expect a native squircle like iconcheck/final.png, not the grey tile in iconcheck/system-rendered.png.
- [no permissions] Log mirror: run `.build/Sill.app/Contents/MacOS/Sill --synthetic` for a few seconds, then kill it. `/usr/bin/log show --last 5m --predicate 'subsystem == "me.saffer.sill.mac"'` should list the same lines. Use /usr/bin/log because zsh's builtin `log` shadows it.
- [no permissions] `git status` and `git diff --stat` should show only the planned files plus the rename. The pre-existing uncommitted hunks in StreamCoordinator.swift, StreamServer.swift and CLAUDE.md must still be there. No host of ours is left running: `pgrep -fl 'SillHost|SillMenuBar|Sill.app/Contents'`.
- [for Noah] First run: quit any SillHost CLI, then `Scripts/make-app.sh --install --open`. Expect the Accessibility alert, then Screen Recording, then possibly Local Network. Enable Sill (not Terminal) in Privacy & Security and accept Quit & Reopen. The menu should show 'Advertising as “<Mac name>”', 'No devices connected', 'Nothing streaming', and both permissions checked.
- [for Noah] The iPad finds the Mac. Within about 2 s a device row appears with fps, frame age and rtt. Pick a window: 'Streaming <App — Window> · 60 fps · <size>' appears and the glyph's iPad fills.
- [for Noah] Controls while streaming, one at a time, with Show Log… open:
- Quality: exactly one new 'Capture started' and 'Streaming … N Mbps'.
- Capture Points: the pixel size halves.
- Frame Rate Limit 60/120: needs a ProMotion device to see a change.
- Virtual Display on: 'Virtual display on (settings)', a display created, 'Moved …', and the window leaves the Mac screen.
- Virtual Display off: 'Restored …' and 'Removed virtual display'.
- [for Noah] Settings… (⌘, while the menu is open) comes to the front and is key. The three tabs stay in sync with the menu. After quit and relaunch the values persist (`defaults read me.saffer.sill.mac`).
- [for Noah] Launch at Login:
- On: Sill is listed in System Settings › General › Login Items, and it is back in the menu bar after logout/login.
- Off: removed.
- Also check that reinstalling in place with --install keeps the login item.
- [for Noah] Permissions: turn Accessibility off in System Settings. The menu shows the warning on its next open, and 'Grant…' opens the right pane. Check both System Settings URLs on macOS 27, and the Local Network hint.
- [for Noah] Quit with a window on the virtual display: the window returns to its frame and no Sill display remains. Repeat with `pkill -TERM -f 'Sill.app/Contents/MacOS/Sill'`, and with logout/restart while streaming.
- [for Noah] The key TCC test: change any code, then `Scripts/make-app.sh --install --open`. There should be no prompts, and streaming and input work immediately. Optional contrast: an ad-hoc build loses both grants silently; recover with `tccutil reset ScreenCapture me.saffer.sill.mac` and `tccutil reset Accessibility me.saffer.sill.mac`.
- [for Noah] Show Log…: lines stream, including the [1s] stats line; ⌘F finds; Copy All and Save… work. `/usr/bin/log stream --predicate 'subsystem == "me.saffer.sill.mac"'` shows the same lines.
- [for Noah] The one behaviour change: with Virtual Display off, click into a background app's window from the iPad. The app should come forward and the first click should land.
- [for Noah] Polish:
- The icon looks native in Finder, Login Items and the Privacy panes.
- Opening Sill.app while it runs opens Settings.
- The glyph reads well on light and dark menu bars (compare glyph1/glyph-sheet.png).
- The virtual display works in the signed, hardened app.

## Code and product maps

### Map 1

This was a read-only map and nothing was edited; the tree is clean on menu-bar-app. SillHost is a single SwiftPM executable target. Its main.swift has top-level code and every type is internal, so a Mac Xcode app can't link it the way the iOS project links StreamProtocol. The plan is to move everything except main.swift into a library target and keep main.swift as the thin CLI. The coordinator's knobs are `let` constants. All of them except virtualDisplay are read only when a pipeline starts, so a settings change can take effect by restarting with select(active). A fresh release build into the scratchpad (.build/ untouched) had 0 errors and 1 warning that was already there, at Sources/CaptureProbe/main.swift:36; SillHost itself has none.

- Package.swift:6 targets macOS 14 / iOS 17. :8-9 products are StreamProtocol (library) and SillHost (executable). :13 SillHost is an executableTarget. :16-17 are the two probes; VirtualDisplayProbe's VirtualDisplay.swift is a symlink to ../SillHost/VirtualDisplay.swift.
- main.swift: knobs at :11-14 (maxFPS 120, scale 2.0, bitrate 15M, prioritizeSpeed false). Flags: preselect :18 (first argument not starting with '--'), --synthetic :22, --virtual-display :28, --encoder-selftest :33-35, --virtual-display-selftest :47-49 (runs its own NSApplication loop, VirtualDisplaySelfTest.swift:12-21). CGMainDisplayID priming at :41, global coordinator at :52.
- startHost is main.swift:54-72: a Task @MainActor creates the coordinator (:57-58), awaits start(preselect:) (:60), prints status (:61-64) and calls Stats.shared.startPrinting() (:65). Its catch prints the Terminal permission hint and calls exit(1) (:67-69). Two run loops: with --virtual-display, :74-83 uses NSApplication, activation policy .prohibited (:80), HostShutdown.install (:81) and app.run(). Otherwise :84-86 calls dispatchMain() with no signal handling.
- HostShutdown.swift:22-34 turns SIGINT/TERM/HUP into signal sources on the main queue and registers atexit VirtualStage.emergencyRestore (:33). begin (:36-48): a second signal exits at once, a 3 s watchdog runs at :42-45, :46 calls shutdownForExit (StreamCoordinator.swift:752-755), then exit at :47. Other exits: StreamServer.swift:96 (listener failed, exit(1)), EncoderSelfTest.swift:47, VirtualDisplaySelfTest.swift:17 and :20. There is no teardown: the server only has start() (:101) and the coordinator has no stop().
- StreamCoordinator init is :91-163 and throws only from StreamServer() at :95. These are `let`: maxFPS :14, scale :28, bitrate :29, prioritizeSpeed :30, synthetic :36, virtualDisplay :42. fps is a private(set) var at :17, set on every select at :386.
- Knob reads in StreamCoordinator.swift: maxFPS :22. fps :27 :118 :314 :427 :501 :519 :522 :526. scale only through captureScale :736, which feeds :427 :453 :460 :465 :482 :829. bitrate :27 (feeds :501 :526). prioritizeSpeed :501. synthetic :167 :457. virtualDisplay :97 (init), :177-187 (start), then :211 :262 :315 :388 :416 :418 :424 :474 :490 :593 :605 :631 :799 :802 :810. A restart is select(active) at :358.
- Stats.swift: startPrinting :63 (main queue, once) arms a timer on .main (:66), every 1 s when active and every 30 s when idle (:30-31). tick prints '[30s] idle · 0 clients · N windows' (:101) or '[1s] <sorted counters> · N clients' (:107). It is fed by bump (:33) from the capture, VideoToolbox and network queues, and by WindowCatalog.swift:58 and :242.
- print( call sites per file, 94 in total: StreamCoordinator 20, VirtualDisplaySelfTest 20, VirtualStage 13, EncoderSelfTest 6, StreamServer 6, WindowSizer 6, main 6, Stats 3, WindowCapture 3, CursorShapeWatcher 2, HostShutdown 2, InputInjector 2, WindowCatalog 2, EncoderProbe 1, HEVCEncoder 1, SyntheticCapture 1, VirtualDisplay 0. Nothing uses Logger, os_log or NSLog.
- VirtualDisplay.swift:37-45: the process must run NSApplication.shared.run() with activation policy .accessory or .prohibited. dispatchMain() never drains the app's event port, so the process never sees the display's modes.
- iOS project file (objectVersion 60, hand-written IDs, one entry per source file): XCLocalSwiftPackageReference with relativePath = .. at :392-397, listed in packageReferences :137-139. XCSwiftPackageProductDependency with productName StreamProtocol at :399-404, listed in the target's packageProductDependencies :106-108. A PBXBuildFile with productRef (:20) sits in the Frameworks phase (:42-50). Generated Info.plist keys are at :314-322. A Mac project beside it can copy this pattern and name the new library product instead.

Risks:
- Xcode can only link library products, and SillHost has no public declarations (the 5 'public ' matches are all in comments). The split needs `public` on what the shell calls: StreamCoordinator init/start/active/catalog/shutdownForExit, Stats.startPrinting, HostShutdown.install and both self-test run() functions.
- Moving the files breaks the VirtualDisplayProbe symlink. Repoint it, or make the probe depend on the new library.
- .prohibited (main.swift:80) means the app can never be activated, so a Settings window can't come to the front. The menu-bar app needs .accessory / LSUIElement; VirtualDisplay.swift:38 lists .accessory as enough for the virtual display.
- activePID(trustAppKit: virtualDisplay) at :605, :631 and :730 uses the flag as a stand-in for 'an AppKit loop is running' (comment at :595-597). An app shell always runs that loop, so changing what this keys on changes how regular mode detects the active app. Untested; needs Noah with Accessibility granted.
- A Finder-launched app throws away stdout, so the Stats line, client stats (StreamServer.swift:176) and fallback notices (StreamCoordinator.swift:175, :434, :766) disappear unless they go to a log sink. The CLI's stdout must stay exactly as it is.
- exit(1) at StreamServer.swift:96 and main.swift:69 would kill the menu-bar app with no message. virtualDisplay is fixed at init and start, and the window restore is installed only under that flag. NSApp.terminate sends no signal, so Quit must call shutdownForExit itself, with the watchdog.
- select returns early while `switching` is set (:359), so a setting changed mid-switch is lost unless it is queued the way viewportArrivedWhileSwitching is.
- The .app is a new TCC identity: Terminal's Screen Recording and Accessibility grants don't carry over, and ad-hoc signed rebuilds reset them. Untested here; steps for Noah.

### Map 2

Read-only pass: nothing was built, run or changed. There's no Mac UI design, no macOS icon and no menu bar glyph yet. The constraints are Developer ID distribution (never the Mac App Store), no sandbox, free and open source, Apple frameworks only, and the SillHost CLI must stay as it is. SwiftPM can't produce a .app. A plain ad-hoc signature ties Screen Recording and Accessibility grants to the binary's cdhash, so they go stale on every rebuild. Signing the bundle with the Apple Development identity already in the keychain fixes that.

- Product rules (/Users/noah/Downloads/winstream/docs/BRIEF.md, CLAUDE.md): free, open source, tip jar, zero servers, no third-party code (Sparkle would need a BRIEF decision). Developer ID plus notarization in M6, never the Mac App Store (private CGVirtualDisplay, Accessibility input), so no sandbox. Developer ID apps can't sell StoreKit tips.
- Polish bar: 'native feel', Flighty-level. All 9 design-canvas artboards are for the device, so the Mac menu has no design yet. Follow macOS convention: template status icon, 'Settings…' ⌘, and 'Quit Sill' ⌘Q.
- Settable today: --virtual-display (Noah flips the default after trying it), --synthetic, the two selftests and a preselect argument. maxFPS, scale, bitrate and prioritizeSpeed are compile-time constants in /Users/noah/Downloads/winstream/Sources/SillHost/main.swift. Permission onboarding is M6 and pairing is M5.
- Run loop: the CLI default path is dispatchMain() and must stay. --virtual-display runs NSApplication.run() with .prohibited, which Apple documents as 'may not create windows or be activated', so the app needs .accessory / LSUIElement.
- Packaging: SwiftPM has no .app product, so this needs a script that assembles and codesigns the bundle, or an Xcode project (the iOS client already has one). Sharing host code with a second executable needs a library target, or one binary that switches mode when it runs inside a bundle.
- Icon assets: /Users/noah/Downloads/winstream/design/AppIcon.svg is the iOS icon (1024 full square, unmasked, its groups meant as Icon Composer layers). /Users/noah/Downloads/winstream/iOSClient/Assets.xcassets/AppIcon.appiconset/AppIcon.png is a 1024 render without alpha. There's no .icns or .icon, no macOS-grid version (824 body in 1024) and no template glyph; an SF Symbol needs no asset. The app icon also shows in the Privacy & Security panes.
- Current signature: .build/release/SillHost is linker-signed ad-hoc, Identifier=SillHost, designated requirement is cdhash H"…", Info.plist not bound. The keychain holds one valid identity, 'Apple Development: … (HG877AGTQ7)'; the iOS project's team is 9B2KKVM937.
- TCC grants belong to the responsible process. Run from Terminal (even Sill.app/Contents/MacOS/<exe> run directly), that is Terminal, which holds today's grants. Launched through LaunchServices (Finder, open, login item), it is the app itself, keyed by CFBundleIdentifier plus a csreq snapshot of its designated requirement.
- Keeping grants across rebuilds: no Info.plist key helps an ad-hoc build. Each rebuild leaves the toggle on but access denied; Noah must re-add it or run tccutil reset ScreenCapture|Accessibility <id>. Codesign the whole bundle, with the plist in place, using the Apple Development identity (requirement = identifier + Apple anchor + leaf CN, stable until the certificate is replaced) or a self-signed code-signing certificate. Ad-hoc with an explicit -r 'designated => identifier …' is uncertain: tccd may not honour it, and it weakens the check.
- Info.plist: choose the final CFBundleIdentifier now (not the iOS app's me.saffer.sill), because TCC, Login Items, defaults and M5 iCloud all key off it. Also CFBundleName Sill, CFBundleExecutable, APPL, versions, icon, LSMinimumSystemVersion 14.0, LSUIElement, and NSLocalNetworkUsageDescription + NSBonjourServices [_sill._tcp]. Local network privacy covers apps on macOS 15+ and exempts tools run from Terminal; exactly what triggers the prompt is uncertain. Screen Recording and Accessibility need no usage-string keys. Use the hardened runtime; no exception entitlements expected (moderate confidence).

Risks:
- All logging is print() to stdout, which is thrown away for an app launched from Finder. The stats and diagnostics CLAUDE.md relies on disappear unless the app writes a log file, uses os.Logger or offers a 'Show Log' item.
- CLI assumptions: exit(1) on startup or listener failure; the messages and README say 'enable Terminal'; InputInjector.launchingAppName() names the parent process, which is launchd for an app.
- Quit, logout and Screen Recording's 'Quit & Reopen' all go through NSApp.terminate. HostShutdown only handles signals and atexit, and only under --virtual-display; nothing hooks applicationWillTerminate. Keep sudden termination off.
- App and CLI running at once: Bonjour renames one of them, and both could put windows on the same fixed 'Sill' display identity (effect uncertain).
- Screen Recording needs a relaunch after granting. macOS 15+ re-asks ScreenCaptureKit apps periodically. The exemption is the managed com.apple.developer.persistent-content-capture entitlement; whether Developer ID apps can get it is uncertain. macOS 27 behaviour is unverified.
- How macOS 26+ displays a full-bleed legacy .icns is uncertain; an Icon Composer .icon compiled by actool is cleaner.
- Nothing that needs Screen Recording or Accessibility was tested here; those checks are steps for Noah.
