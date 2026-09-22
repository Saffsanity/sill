// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Sill",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "StreamProtocol", targets: ["StreamProtocol"]),
        .executable(name: "SillHost", targets: ["SillHost"]),
    ],
    targets: [
        .target(name: "StreamProtocol"),
        .executableTarget(name: "SillHost", dependencies: ["StreamProtocol"]),
        // Milestone 3 spike: virtual display + window move + capture. Its VirtualDisplay.swift
        // is a symlink to the host's copy. Not shipped.
        .executableTarget(name: "VirtualDisplayProbe"),
    ]
)
