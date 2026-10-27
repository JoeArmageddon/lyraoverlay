// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "LyraCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LyraCore", targets: ["LyraCore"]),
        .executable(name: "lyra-cli", targets: ["lyra-cli"]),
    ],
    targets: [
        .target(
            name: "LyraCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "lyra-cli",
            dependencies: ["LyraCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "LyraCoreTests",
            dependencies: ["LyraCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
