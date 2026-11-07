// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Hummery",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Hummery", targets: ["Hummery"])],
    targets: [
        .target(name: "PlayerCore"),
        .executableTarget(name: "Hummery", dependencies: ["PlayerCore"]),
        .testTarget(name: "PlayerCoreTests", dependencies: ["PlayerCore"]),
        .testTarget(name: "HummeryTests", dependencies: ["Hummery", "PlayerCore"])
    ]
)
