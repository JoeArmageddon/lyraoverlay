// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "LyraSpikes",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "overlay-spike",
            path: "Sources/overlay-spike",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "overlay-variants",
            path: "Sources/overlay-variants",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "audio-spike",
            path: "Sources/audio-spike",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
