// swift-tools-version:6.0
import PackageDescription

// Generates Lyra's original display fonts as real TrueType files. No third-party code and no
// network access: the font file writer, the glyph skeletons and the style transforms are all here.
let package = Package(
    name: "FontFactory",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "FontFactoryCore", swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "fontfactory", dependencies: ["FontFactoryCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "FontFactoryTests", dependencies: ["FontFactoryCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
