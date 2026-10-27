import AppKit
import ImageIO
import XCTest
@testable import LyraCore

// MARK: - Helpers

/// RGBA8 pixels for a `width` x `height` image, colored by `color(x, y)`.
private func pixels(_ width: Int, _ height: Int, _ color: (Int, Int) -> (UInt8, UInt8, UInt8)) -> [UInt8] {
    var out = [UInt8](repeating: 255, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let (r, g, b) = color(x, y)
            let o = (y * width + x) * 4
            out[o] = r; out[o + 1] = g; out[o + 2] = b
        }
    }
    return out
}

private func cgImage(_ data: [UInt8], _ width: Int, _ height: Int) -> CGImage {
    let provider = CGDataProvider(data: Data(data) as CFData)!
    return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                   space: CGColorSpace(name: CGColorSpace.sRGB)!,
                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                   provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
}

private func pngData(_ image: CGImage) -> Data {
    let out = NSMutableData()
    let dest = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
    return out as Data
}

private func isRedish(_ c: RGBA) -> Bool { c.r > 0.75 && c.g < 0.25 && c.b < 0.25 }
private func isBluish(_ c: RGBA) -> Bool { c.b > 0.75 && c.r < 0.25 && c.g < 0.25 }
private func spread(_ c: RGBA) -> Float { max(c.r, c.g, c.b) - min(c.r, c.g, c.b) }

// MARK: - Extraction

final class PaletteExtractorTests: XCTestCase {
    private let redBlue = pixels(40, 40) { x, _ in x < 20 ? (255, 0, 0) : (0, 0, 255) }

    func testRedAndBlueHalvesGiveRedAndBlueSwatches() throws {
        let palette = try XCTUnwrap(PaletteExtractor.extract(pixels: redBlue, width: 40, height: 40))
        XCTAssertTrue(palette.swatches.contains(where: isRedish), "swatches: \(palette.swatches)")
        XCTAssertTrue(palette.swatches.contains(where: isBluish), "swatches: \(palette.swatches)")
        XCTAssertGreaterThan(spread(palette.accent), 0.5, "the accent is a vivid color")
        XCTAssertTrue(isRedish(palette.secondary) || isBluish(palette.secondary))
        XCTAssertNotEqual(palette.dominant, palette.secondary)
    }

    func testSolidGrayDoesNotCrashAndHasLowChroma() throws {
        let gray = pixels(30, 30) { _, _ in (128, 128, 128) }
        let palette = try XCTUnwrap(PaletteExtractor.extract(pixels: gray, width: 30, height: 30))
        XCTAssertEqual(palette.swatches.count, 1)
        for c in [palette.dominant, palette.accent, palette.secondary] { XCTAssertLessThan(spread(c), 0.04) }
        XCTAssertNotEqual(palette.secondary, palette.dominant, "secondary still contrasts with a one-color image")
    }

    func testSmallSaturatedPatchOnBlackBecomesTheAccent() throws {
        // 25x25 of 100x100 is 6% of the image: small, but a real part of it.
        let art = pixels(100, 100) { x, y in (x < 25 && y < 25) ? (0, 200, 0) : (0, 0, 0) }
        let palette = try XCTUnwrap(PaletteExtractor.extract(pixels: art, width: 100, height: 100))
        XCTAssertLessThan(max(palette.dominant.r, palette.dominant.g, palette.dominant.b), 0.15, "dominant is the dark background")
        XCTAssertGreaterThan(palette.accent.g, 0.6)
        XCTAssertLessThan(palette.accent.r, 0.2)
        XCTAssertLessThan(palette.accent.b, 0.2)
        XCTAssertTrue(palette.isDark)
    }

    func testStrayPixelsCannotBeTheAccent() throws {
        // 3 vivid pixels in 10,000 (0.03%) are noise, not the artwork's accent.
        let art = pixels(100, 100) { x, y in (y == 0 && x < 3) ? (255, 0, 255) : (90, 90, 90) }
        let palette = try XCTUnwrap(PaletteExtractor.extract(pixels: art, width: 100, height: 100))
        XCTAssertLessThan(spread(palette.accent), 0.1)
    }

    func testLightPrimaryIsBrighterWhenTheAccentIsDark() throws {
        let art = pixels(60, 60) { x, _ in x < 20 ? (110, 0, 10) : (0, 0, 0) }
        let palette = try XCTUnwrap(PaletteExtractor.extract(pixels: art, width: 60, height: 60))
        let accentLuma = ColorMath.luma(palette.accent)
        let lifted = palette.lightPrimary
        XCTAssertGreaterThan(ColorMath.luma(lifted), accentLuma + 0.1)
        XCTAssertGreaterThanOrEqual(ColorMath.lab(from: lifted).x, Palette.minimumGlowLightness - 1)
        XCTAssertGreaterThan(lifted.r, lifted.g, "hue stays red")
        XCTAssertEqual(lifted.a, 1)
    }

    func testLightPrimaryLeavesAnAlreadyLightAccentAlone() {
        let bright = RGBA(1, 0.9, 0.4, 1)
        let palette = Palette(dominant: .white, accent: bright, secondary: bright, swatches: [bright], isDark: false)
        XCTAssertEqual(palette.lightPrimary, bright)
    }

    func testSameInputGivesIdenticalOutput() throws {
        let art = pixels(64, 64) { x, y in (UInt8(x * 4), UInt8(y * 4), UInt8((x * y) % 256)) }
        let a = try XCTUnwrap(PaletteExtractor.extract(pixels: art, width: 64, height: 64))
        let b = try XCTUnwrap(PaletteExtractor.extract(pixels: art, width: 64, height: 64))
        XCTAssertEqual(a, b)
    }

    func testEmptyOrMalformedInputGivesNil() {
        XCTAssertNil(PaletteExtractor.extract(pixels: [], width: 0, height: 0))
        XCTAssertNil(PaletteExtractor.extract(pixels: [255, 0, 0, 255], width: 0, height: 1))
        XCTAssertNil(PaletteExtractor.extract(pixels: [255, 0, 0, 255], width: 2, height: 2), "too few pixels for the size")
        XCTAssertNil(PaletteExtractor.extract(pixels: redBlue, width: 40, height: 40, k: 0))
    }

    func testFullyTransparentImageGivesNil() {
        var art = pixels(10, 10) { _, _ in (255, 0, 0) }
        for i in stride(from: 3, to: art.count, by: 4) { art[i] = 0 }
        XCTAssertNil(PaletteExtractor.extract(pixels: art, width: 10, height: 10))
    }

    func testDarkAndLightImagesAreClassified() throws {
        let black = pixels(10, 10) { _, _ in (0, 0, 0) }
        let white = pixels(10, 10) { _, _ in (255, 255, 255) }
        XCTAssertTrue(try XCTUnwrap(PaletteExtractor.extract(pixels: black, width: 10, height: 10)).isDark)
        XCTAssertFalse(try XCTUnwrap(PaletteExtractor.extract(pixels: white, width: 10, height: 10)).isDark)
    }

    func testCGImageEntryPointDownsamplesAndFindsTheColors() throws {
        let big = cgImage(pixels(600, 600) { x, _ in x < 300 ? (255, 0, 0) : (0, 0, 255) }, 600, 600)
        let palette = try XCTUnwrap(PaletteExtractor.extract(from: big))
        XCTAssertTrue(palette.swatches.contains(where: isRedish))
        XCTAssertTrue(palette.swatches.contains(where: isBluish))
    }

    func testLargeImagesAreSubsampledNotRejected() throws {
        let art = pixels(512, 512) { x, _ in x < 256 ? (255, 0, 0) : (0, 0, 255) }   // 262k pixels, over the point cap
        let palette = try XCTUnwrap(PaletteExtractor.extract(pixels: art, width: 512, height: 512))
        XCTAssertTrue(palette.swatches.contains(where: isRedish))
    }
}

final class ColorMathTests: XCTestCase {
    func testLabRoundTripIsLossless() {
        for (r, g, b) in [(0.0, 0.0, 0.0), (1.0, 1.0, 1.0), (0.8, 0.2, 0.4), (0.1, 0.9, 0.5), (0.5, 0.5, 0.5)] {
            let back = ColorMath.rgba(from: ColorMath.lab(r: r, g: g, b: b))
            XCTAssertEqual(Double(back.r), r, accuracy: 1.0 / 255)
            XCTAssertEqual(Double(back.g), g, accuracy: 1.0 / 255)
            XCTAssertEqual(Double(back.b), b, accuracy: 1.0 / 255)
        }
    }

    func testKnownLabValues() {
        XCTAssertEqual(ColorMath.lab(r: 1, g: 1, b: 1).x, 100, accuracy: 0.1)
        XCTAssertEqual(ColorMath.lab(r: 0, g: 0, b: 0).x, 0, accuracy: 0.1)
        let red = ColorMath.lab(r: 1, g: 0, b: 0)
        XCTAssertEqual(red.x, 53.2, accuracy: 0.5)
        XCTAssertEqual(red.y, 80.1, accuracy: 0.8)
    }

    func testOutOfGamutColorsKeepLightnessAndFitInRange() {
        // Very high chroma at mid lightness is far outside sRGB.
        let c = ColorMath.rgba(from: SIMD3(60, 120, -90))
        for v in [c.r, c.g, c.b] { XCTAssertTrue((0...1).contains(v)) }
        XCTAssertEqual(ColorMath.lab(from: c).x, 60, accuracy: 3)
    }
}

// MARK: - Theme

final class ThemeResolverTests: XCTestCase {
    private let palette = Palette(
        dominant: RGBA(0.2, 0.1, 0.4, 1), accent: RGBA(0.9, 0.3, 0.2, 1), secondary: RGBA(0.1, 0.5, 0.8, 1),
        swatches: [], isDark: true)

    func testPalettePathRetintsTheColors() {
        let config = OverlayConfig()
        let themed = ThemeResolver.resolve(config, palette: palette, useArtworkColors: true)

        XCTAssertEqual(themed.glowColor, palette.lightPrimary)
        XCTAssertEqual(themed.highlightColor.a, 1)
        XCTAssertEqual(themed.baseColor.a, config.baseColor.a, "unsung opacity is the config's, not the palette's")

        // Sung words stay near white: closer to white than to the glow color.
        func dist(_ a: RGBA, _ b: RGBA) -> Float { abs(a.r - b.r) + abs(a.g - b.g) + abs(a.b - b.b) }
        XCTAssertLessThan(dist(themed.highlightColor, .white), dist(themed.highlightColor, themed.glowColor))
        XCTAssertNotEqual(themed.highlightColor, config.highlightColor, "but tinted, not pure white")

        // 18% of the way from white to the glow color, per channel.
        XCTAssertEqual(themed.highlightColor.r, 1 + (themed.glowColor.r - 1) * 0.18, accuracy: 1e-5)
        // 20% of the way from white to the dominant color.
        XCTAssertEqual(themed.baseColor.g, 1 + (palette.dominant.g - 1) * 0.2, accuracy: 1e-5)
    }

    func testOtherSettingsAreUntouched() {
        var config = OverlayConfig()
        config.glow = 0.9
        config.latencyOffset = 0.4
        let themed = ThemeResolver.resolve(config, palette: palette, useArtworkColors: true)
        XCTAssertEqual(themed.glow, 0.9)
        XCTAssertEqual(themed.latencyOffset, 0.4)
        XCTAssertEqual(themed.font, config.font)
    }

    func testDisabledOrMissingPaletteReturnsTheConfigUnchanged() {
        let config = OverlayConfig()
        XCTAssertEqual(ThemeResolver.resolve(config, palette: palette, useArtworkColors: false), config)
        XCTAssertEqual(ThemeResolver.resolve(config, palette: nil, useArtworkColors: true), config)
        XCTAssertEqual(ThemeResolver.resolve(config, palette: nil, useArtworkColors: false), config)
    }
}

// MARK: - Artwork

private struct MockScripts: ScriptRunning {
    var handler: @Sendable (String) -> Result<String, ScriptError>
    func run(_ source: String) async -> Result<String, ScriptError> { handler(source) }
}

private final class CountingHTTP: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [URL] = []
    var requests: [URL] { lock.withLock { _requests } }
    let status: Int
    let body: Data
    init(status: Int = 200, body: Data) { self.status = status; self.body = body }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { _requests.append(request.url!) }
        return (body, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

final class ArtworkProviderTests: XCTestCase {
    private let sep = "\u{1F}"
    private let png = pngData(cgImage(pixels(8, 6) { _, _ in (200, 30, 30) }, 8, 6))

    private func track(_ player: PlayerKind, id: String = "abc") -> Track {
        Track(title: "T", artist: "A", album: "B", duration: 100, player: player, id: id)
    }

    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lyra-art-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Pulls the destination path out of the Music script, the way osascript would receive it.
    private static func path(in script: String) -> String? {
        guard let r = script.range(of: #"POSIX file "[^"]+""#, options: .regularExpression) else { return nil }
        return String(script[r]).replacingOccurrences(of: "POSIX file \"", with: "").dropLast().description
    }

    func testDecoderReadsPNGAndRejectsGarbage() throws {
        let image = try XCTUnwrap(ArtworkDecoder.image(from: png))
        XCTAssertEqual(image.width, 8)
        XCTAssertEqual(image.height, 6)
        XCTAssertNil(ArtworkDecoder.image(from: Data("not an image".utf8)))
        XCTAssertNil(ArtworkDecoder.image(from: Data()))
    }

    func testSpotifyDownloadsTheArtworkURL() async throws {
        let http = CountingHTTP(body: png)
        let provider = PlayerArtworkProvider(
            http: http, runner: MockScripts { _ in .success("abc\(self.sep)https://example.com/cover.jpg") }, tempDirectory: tempDir())
        let image = await provider.artwork(for: track(.spotify))
        XCTAssertEqual(image?.width, 8)
        XCTAssertEqual(http.requests.map(\.absoluteString), ["https://example.com/cover.jpg"])
    }

    func testSpotifyTrackIDMismatchIsDiscardedWithoutDownloading() async {
        let http = CountingHTTP(body: png)
        let provider = PlayerArtworkProvider(
            http: http, runner: MockScripts { _ in .success("other\(self.sep)https://example.com/cover.jpg") }, tempDirectory: tempDir())
        let image = await provider.artwork(for: track(.spotify))
        XCTAssertNil(image)
        XCTAssertTrue(http.requests.isEmpty)
    }

    func testSpotifyFailuresGiveNil() async {
        let url = "abc\(sep)https://example.com/cover.jpg"
        let notFound = PlayerArtworkProvider(http: CountingHTTP(status: 404, body: png), runner: MockScripts { _ in .success(url) }, tempDirectory: tempDir())
        let noImage = await notFound.artwork(for: track(.spotify))
        XCTAssertNil(noImage)

        let garbage = PlayerArtworkProvider(http: CountingHTTP(body: Data("nope".utf8)), runner: MockScripts { _ in .success(url) }, tempDirectory: tempDir())
        let badData = await garbage.artwork(for: track(.spotify))
        XCTAssertNil(badData)

        let scriptFails = PlayerArtworkProvider(http: CountingHTTP(body: png), runner: MockScripts { _ in .failure(.notAuthorized) }, tempDirectory: tempDir())
        let denied = await scriptFails.artwork(for: track(.spotify))
        XCTAssertNil(denied)

        let noURL = PlayerArtworkProvider(http: CountingHTTP(body: png), runner: MockScripts { _ in .success("abc") }, tempDirectory: tempDir())
        let truncated = await noURL.artwork(for: track(.spotify))
        XCTAssertNil(truncated)
    }

    func testMusicReadsTheFileTheScriptWroteThenDeletesIt() async throws {
        let dir = tempDir()
        let png = self.png
        let sep = self.sep
        let provider = PlayerArtworkProvider(
            http: CountingHTTP(body: Data()),
            runner: MockScripts { script in
                guard let path = Self.path(in: script) else { return .failure(.failed(code: -1, message: "no path")) }
                try? png.write(to: URL(fileURLWithPath: path))
                return .success("abc\(sep)ok")
            },
            tempDirectory: dir)
        let image = await provider.artwork(for: track(.appleMusic))
        XCTAssertEqual(image?.height, 6)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), [], "temp file is cleaned up")
    }

    func testMusicMismatchNoArtworkAndErrorsGiveNilAndLeaveNoFiles() async throws {
        let png = self.png
        let sep = self.sep
        for reply in ["other\(sep)ok", "abc\(sep)none", "abc\(sep)error", ""] {
            let dir = tempDir()
            let provider = PlayerArtworkProvider(
                http: CountingHTTP(body: Data()),
                runner: MockScripts { script in
                    if let path = Self.path(in: script) { try? png.write(to: URL(fileURLWithPath: path)) }
                    return .success(reply)
                },
                tempDirectory: dir)
            let image = await provider.artwork(for: track(.appleMusic))
            XCTAssertNil(image, "reply \(reply.debugDescription)")
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), [], "reply \(reply.debugDescription)")
        }
    }

    func testMusicScriptEscapesThePath() {
        let script = PlayerArtworkProvider.musicScript(writingTo: "/tmp/we\"ird\\name.bin")
        XCTAssertTrue(script.contains(#"POSIX file "/tmp/we\"ird\\name.bin""#))
    }

    /// Regression guard, like `testPlayerScriptsCompile`: a variable that clashes with an app's
    /// dictionary fails to compile, and failures like that are otherwise silent.
    func testArtworkScriptsCompile() throws {
        let scripts: [(String, String)] = [
            ("com.spotify.client", PlayerArtworkProvider.spotifyScript),
            ("com.apple.Music", PlayerArtworkProvider.musicScript(writingTo: "/tmp/lyra-compile-check.bin")),
        ]
        for (bundleID, source) in scripts {
            guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil else { continue }
            var error: NSDictionary?
            let script = try XCTUnwrap(NSAppleScript(source: source))
            XCTAssertTrue(script.compileAndReturnError(&error), "\(bundleID) script failed to compile: \(String(describing: error))")
        }
    }
}

final class PaletteCacheTests: XCTestCase {
    private func palette(_ v: Float) -> Palette {
        Palette(dominant: RGBA(v, v, v, 1), accent: .white, secondary: .white, swatches: [], isDark: false)
    }

    func testStoresAndReturnsByKey() {
        var cache = PaletteCache(capacity: 3)
        cache.store(palette(0.1), for: "a")
        XCTAssertEqual(cache.palette(for: "a"), palette(0.1))
        XCTAssertNil(cache.palette(for: "b"))
    }

    func testEvictsTheOldestBeyondCapacity() {
        var cache = PaletteCache(capacity: 2)
        cache.store(palette(0.1), for: "a")
        cache.store(palette(0.2), for: "b")
        cache.store(palette(0.3), for: "c")
        XCTAssertNil(cache.palette(for: "a"))
        XCTAssertNotNil(cache.palette(for: "b"))
        XCTAssertNotNil(cache.palette(for: "c"))
        XCTAssertEqual(cache.count, 2)
    }

    func testRestoringAKeyDoesNotGrowOrReorderTheCache() {
        var cache = PaletteCache(capacity: 2)
        cache.store(palette(0.1), for: "a")
        cache.store(palette(0.2), for: "b")
        cache.store(palette(0.5), for: "a")   // update in place
        XCTAssertEqual(cache.count, 2)
        XCTAssertEqual(cache.palette(for: "a"), palette(0.5))
    }
}
