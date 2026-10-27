// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "LyraApp",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "lyra-app", targets: ["lyra-app"]),
    ],
    dependencies: [
        .package(path: "../LyraCore"),
    ],
    targets: [
        // Metal rendering, text rasterizing and overlay windows. A library so tests can reach it.
        .target(
            name: "LyraRender",
            dependencies: [.product(name: "LyraCore", package: "LyraCore")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "lyra-app",
            dependencies: ["LyraRender", .product(name: "LyraCore", package: "LyraCore")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "LyraRenderTests",
            dependencies: ["LyraRender", .product(name: "LyraCore", package: "LyraCore")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
