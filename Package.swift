// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Cermin",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure logic: no AppKit/AVFoundation, fully unit-tested.
        .target(name: "CerminCore"),
        .executableTarget(name: "Cermin", dependencies: ["CerminCore"]),
        .testTarget(name: "CerminCoreTests", dependencies: ["CerminCore"]),
    ]
)
