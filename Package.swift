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
        // Sill Camera, the Core Media I/O camera extension (docs/camera-plan.md §7): Scripts/make-app.sh embeds it in
        // Sill.app with SILL_CAMERA_EXTENSION=1. macOS only.
        .executable(name: "SillCameraExtension", targets: ["SillCameraExtension"]),
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
        // The menu bar app: status item, Settings and Log windows (AppKit lifecycle, SwiftUI panes), and Sill Camera's
        // feed (CameraSink) and installation (CameraExtensionManager).
        .executableTarget(name: "SillMenuBar", dependencies: ["SillHostCore", "StreamProtocol", "CameraFeed"]),
        // Sill Camera's rules (CameraFeedPolicy, docs/camera-plan.md §6.4) and Sill.app's side of its feed
        // (CameraSinkPolicy), shared by the extension and Sill.app's sink: Foundation only, and no product, so the iOS
        // project never sees it.
        .target(name: "CameraFeed"),
        // Sill Camera itself: run by macOS as its own sandboxed process once Sill for Mac activated it.
        .executableTarget(name: "SillCameraExtension", dependencies: ["CameraFeed"]),
        // Milestone 3 spike: virtual display + window move + capture. Its VirtualDisplay.swift
        // is a symlink to the host's copy. Not shipped.
        .executableTarget(name: "CaptureProbe"),
        .executableTarget(name: "VirtualDisplayProbe"),
    ]
)
