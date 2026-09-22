// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "winstream",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "StreamProtocol", targets: ["StreamProtocol"]),
        .executable(name: "WinStreamHost", targets: ["WinStreamHost"]),
    ],
    targets: [
        .target(name: "StreamProtocol"),
        .executableTarget(name: "WinStreamHost", dependencies: ["StreamProtocol"]),
    ]
)
