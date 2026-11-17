// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FarmMac",
    platforms: [.macOS(.v26)],
    targets: [
        // Pure logic (report parsing, upload chunking), unit tested.
        .target(name: "FarmCore"),
        .executableTarget(name: "FarmMac", dependencies: ["FarmCore"]),
        .testTarget(name: "FarmCoreTests", dependencies: ["FarmCore"]),
    ]
)
