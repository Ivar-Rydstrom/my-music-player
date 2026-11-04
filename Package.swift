// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StillPlayer",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "StillPlayer", targets: ["StillPlayer"])],
    targets: [
        .target(name: "PlayerCore"),
        .executableTarget(name: "StillPlayer", dependencies: ["PlayerCore"]),
        .testTarget(name: "PlayerCoreTests", dependencies: ["PlayerCore"])
    ]
)
