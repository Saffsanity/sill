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
    ]
)
