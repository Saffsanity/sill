// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Sill",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "StreamProtocol", targets: ["StreamProtocol"]),
        // The CLI keeps the product name SillHost, so `swift run -c release SillHost …` and
        // .build/release/SillHost are what they always were.
        .executable(name: "SillHost", targets: ["SillHostCLI"]),
        // Sill.app's executable. Scripts/make-app.sh wraps it into the bundle and signs it.
        .executable(name: "SillMenuBar", targets: ["SillMenuBar"]),
        // The Mac client: view and control another Mac's Sill host. Scripts/make-client-app.sh wraps it.
        .executable(name: "SillClient", targets: ["MacClient"]),
        .executable(name: "SillDockProxy", targets: ["SillDockProxy"]),
        // No product for SillHostCore: the iOS project links this package and must never see it.
    ],
    targets: [
        .target(name: "StreamProtocol"),
        // The Mac host itself (capture, encode, network, input, virtual display), shared by the CLI
        // and the menu bar app; they reach it through `package` access. The folder keeps its old
        // name (Sources/SillHost) so the paths in the docs and the VirtualDisplayProbe symlink to
        // ../SillHost/VirtualDisplay.swift stay valid.
        .target(name: "SillHostCore", dependencies: ["StreamProtocol"], path: "Sources/SillHost"),
        // The command-line host: flags, the run loop, the Terminal permission hint.
        .executableTarget(name: "SillHostCLI", dependencies: ["SillHostCore", "StreamProtocol"]),
        // The menu bar app: status item, Settings and Log windows (AppKit lifecycle, SwiftUI panes).
        .executableTarget(name: "SillMenuBar", dependencies: ["SillHostCore", "StreamProtocol"]),
        // The Mac client (docs/mac-client-plan.md). Its Shared folder holds symlinks to the iOS
        // app's session code (StreamClient and its policies), compiled here unchanged, as
        // VirtualDisplayProbe links the host's VirtualDisplay.swift; Sources/MacClient has the
        // AppKit and SwiftUI side.
        .executableTarget(name: "MacClient", dependencies: ["StreamProtocol"]),
        // A Dock icon for one of the other Mac's apps: Sill Viewer carries it in Contents/Helpers and
        // makes a named copy per remote app (DockProxies).
        .executableTarget(name: "SillDockProxy"),
        // Milestone 3 spike: virtual display + window move + capture. Its VirtualDisplay.swift
        // is a symlink to the host's copy. Not shipped.
        .executableTarget(name: "CaptureProbe"),
        .executableTarget(name: "VirtualDisplayProbe"),
    ]
)
