// swift-tools-version:5.9
// Sill sizzle reel renderer. Apple frameworks only (SwiftUI ImageRenderer, Core Graphics, Core Image,
// AVFoundation). Tools/ReelRenderer in the Sill repository: a package of its own, which the root Package.swift
// does not name, so neither the app's build nor CI builds it (README.md).
import PackageDescription

let package = Package(
    name: "ReelRenderer",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "ReelRenderer", path: "Sources/ReelRenderer",
                          swiftSettings: [.unsafeFlags(["-O"])])
    ]
)
