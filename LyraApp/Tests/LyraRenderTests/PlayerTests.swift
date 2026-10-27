import XCTest
import AppKit
import AVFoundation
import ImageIO
import UniformTypeIdentifiers
import LyraCore
@testable import LyraRender

// MARK: - Helpers

private func tempDir(_ tag: String = "player") -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("lyra-\(tag)-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func makeImage(_ color: (UInt8, UInt8, UInt8), size: Int = 200) -> CGImage {
    var pixels = [UInt8](repeating: 255, count: size * size * 4)
    for i in 0..<(size * size) { pixels[i * 4] = color.0; pixels[i * 4 + 1] = color.1; pixels[i * 4 + 2] = color.2 }
    return CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
                   space: CGColorSpace(name: CGColorSpace.sRGB)!,
                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                   provider: CGDataProvider(data: Data(pixels) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
}

@discardableResult
private func writePNG(_ color: (UInt8, UInt8, UInt8), to url: URL) -> URL {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, makeImage(color), nil)
    XCTAssertTrue(CGImageDestinationFinalize(dest))
    return url
}

/// A short H.264 movie whose color flips between `a` and `b` every second.
private func makeVideo(at url: URL, a: (UInt8, UInt8, UInt8), b: (UInt8, UInt8, UInt8), seconds: Int = 4) throws {
    let size = 64, fps = 10
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: size, AVVideoHeightKey: size])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: size, kCVPixelBufferHeightKey as String: size])
    writer.add(input)
    XCTAssertTrue(writer.startWriting())
    writer.startSession(atSourceTime: .zero)
    for frame in 0..<(seconds * fps) {
        while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.005) }
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, size, size, kCVPixelFormatType_32BGRA, nil, &buffer)
        let pb = try XCTUnwrap(buffer)
        CVPixelBufferLockBaseAddress(pb, [])
        let base = CVPixelBufferGetBaseAddress(pb)!.assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(pb)
        let c = (frame / fps) % 2 == 0 ? a : b
        for y in 0..<size { for x in 0..<size {
            let p = base + y * stride + x * 4
            p[0] = c.2; p[1] = c.1; p[2] = c.0; p[3] = 255
        } }
        CVPixelBufferUnlockBaseAddress(pb, [])
        XCTAssertTrue(adaptor.append(pb, withPresentationTime: CMTime(value: Int64(frame), timescale: Int32(fps))))
    }
    input.markAsFinished()
    let done = DispatchSemaphore(value: 0)
    writer.finishWriting { done.signal() }
    done.wait()
    guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
}

/// Runs the main run loop until `condition` holds or `timeout` passes; returns whether it held.
@discardableResult
private func waitUntil(_ timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
    let end = Date().addingTimeInterval(timeout)
    while !condition(), Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    return condition()
}

private func palette(_ c: RGBA) -> Palette { Palette(dominant: c, accent: c, secondary: c, swatches: [c], isDark: true) }

// MARK: - Frame builder (pure)

final class PlayerFrameBuilderTests: XCTestCase {
    private let album = Palette(dominant: RGBA(0.1, 0.1, 0.3), accent: RGBA(0.9, 0.2, 0.2), secondary: RGBA(0.2, 0.2, 0.9),
                                swatches: [], isDark: true)
    private let background = Palette(dominant: RGBA(0.1, 0.3, 0.1), accent: RGBA(0.1, 0.8, 0.3), secondary: RGBA(0.9, 0.8, 0.1),
                                     swatches: [], isDark: true)

    func testFontScaleFollowsTheWindowWidth() {
        XCTAssertEqual(PlayerFrameBuilder.fontScale(viewportWidth: 1440, lyricsScale: 1), 1, accuracy: 1e-9)
        XCTAssertEqual(PlayerFrameBuilder.fontScale(viewportWidth: 2880, lyricsScale: 1), 2, accuracy: 1e-9)
        XCTAssertEqual(PlayerFrameBuilder.fontScale(viewportWidth: 720, lyricsScale: 1), 0.5, accuracy: 1e-9)
        XCTAssertEqual(PlayerFrameBuilder.fontScale(viewportWidth: 1440, lyricsScale: 1.5), 1.5, accuracy: 1e-9)
        XCTAssertEqual(PlayerFrameBuilder.fontScale(viewportWidth: 10, lyricsScale: 1), 0.25, accuracy: 1e-9, "never vanishes in a tiny window")
    }

    func testLyricConfigScalesTextAndCentersIt() {
        var base = OverlayConfig()
        base.font = FontSpec(family: "Menlo-Bold", size: 40, weight: 0.3, tracking: 0.05, italic: true)
        base.anchorY = 0.16
        let config = PlayerFrameBuilder.lyricConfig(base: base, albumPalette: nil, useArtworkColors: true, viewportWidth: 2880, lyricsScale: 1)
        XCTAssertEqual(config.font.size, 80, accuracy: 1e-9)
        XCTAssertEqual(config.anchorY, 0.5, "centered vertically, whatever the overlay uses")
        XCTAssertEqual(config.font.family, "Menlo-Bold")
        XCTAssertEqual(config.font.tracking, 0.05)
        XCTAssertTrue(config.font.italic)
        XCTAssertEqual(config.maxWidthFraction, base.maxWidthFraction)
        XCTAssertEqual(config.showNextLine, base.showNextLine)
    }

    func testAlbumColorsApplyOnlyWhenOnAndAvailable() {
        let base = OverlayConfig()
        func glow(_ p: Palette?, _ on: Bool) -> RGBA {
            PlayerFrameBuilder.lyricConfig(base: base, albumPalette: p, useArtworkColors: on, viewportWidth: 1440, lyricsScale: 1).glowColor
        }
        XCTAssertEqual(glow(album, true), album.lightPrimary)
        XCTAssertEqual(glow(album, false), base.glowColor)
        XCTAssertEqual(glow(nil, true), base.glowColor)
    }

    func testBorderSourceFallbackOrder() {
        XCTAssertEqual(PlayerFrameBuilder.borderSource(background: background, album: album, followBackground: true), background)
        XCTAssertEqual(PlayerFrameBuilder.borderSource(background: nil, album: album, followBackground: true), album, "no background colors yet")
        XCTAssertEqual(PlayerFrameBuilder.borderSource(background: background, album: album, followBackground: false), album)
        XCTAssertNil(PlayerFrameBuilder.borderSource(background: nil, album: nil, followBackground: true))
        XCTAssertEqual(PlayerFrameBuilder.borderSource(background: background, album: nil, followBackground: false), nil,
                       "not following the background and no album: defaults")
    }

    func testBorderColorsComeFromThePaletteElseTheDefaults() {
        let colors = PlayerFrameBuilder.borderColors(from: background)
        XCTAssertEqual(colors.primary, background.lightPrimary)
        XCTAssertEqual(colors.secondary, background.lightSecondary)
        let defaults = PlayerFrameBuilder.borderColors(from: nil)
        XCTAssertEqual(defaults.primary, RimGlowEffect.defaultPrimary)
        XCTAssertEqual(defaults.secondary, RimGlowEffect.defaultSecondary)
    }

    func testBorderThicknessScalesWithinLimits() {
        var config = LightConfig()
        config.thickness = 36
        config.intensity = 0.7
        func thickness(_ width: CGFloat) -> Double { PlayerFrameBuilder.borderConfig(config, viewportWidth: width).thickness }
        XCTAssertEqual(thickness(1440), 36, accuracy: 1e-9)
        XCTAssertEqual(thickness(2160), 54, accuracy: 1e-9)
        XCTAssertEqual(thickness(8000), 72, accuracy: 1e-9, "at most double")
        XCTAssertEqual(thickness(720), 18, accuracy: 1e-9)
        XCTAssertEqual(thickness(100), 18, accuracy: 1e-9, "at least half")
        XCTAssertEqual(PlayerFrameBuilder.borderConfig(config, viewportWidth: 2000).intensity, 0.7, "only thickness changes")
    }

    func testLightParamsUseThePaletteAndHonorTheConfig() throws {
        let effect = RimGlowEffect()
        var config = LightConfig()
        config.thickness = 40
        let params = try XCTUnwrap(PlayerFrameBuilder.lightParams(effect: effect, features: nil, palette: background, config: config,
                                                                  viewportWidth: 2880, time: 1))
        XCTAssertEqual(params.primary, background.lightPrimary)
        XCTAssertEqual(params.secondary, background.lightSecondary)
        XCTAssertEqual(params.thickness, 80, accuracy: 1e-9, "scaled for a window twice the reference width")
        XCTAssertGreaterThan(params.intensity, 0, "without audio it still breathes")

        config.enabled = false
        XCTAssertNil(PlayerFrameBuilder.lightParams(effect: effect, features: nil, palette: background, config: config, viewportWidth: 1440, time: 1))
    }

    func testBorderColorsGlideWhenTheBackgroundChanges() {
        var smoother = PaletteSmoother(timeConstant: 0.5)
        _ = smoother.update(target: palette(RGBA(1, 0, 0)), dt: 0)
        let after = smoother.update(target: palette(RGBA(0, 0, 1)), dt: 1.0)   // a second later
        let colors = PlayerFrameBuilder.borderColors(from: after)
        XCTAssertGreaterThan(colors.primary.b, 0.5, "mostly there after about a second")
        XCTAssertLessThan(after.accent.r, 0.2)
        XCTAssertGreaterThan(after.accent.r, 0, "but not a jump")
    }
}

final class LyricsCaseCacheTests: XCTestCase {
    private func document(_ text: String) throws -> LyricsDocument {
        try XCTUnwrap(LRCParser.parse("[00:01.00]\(text)\n[00:05.00]second line"))
    }

    func testAsWrittenIsUntouched() throws {
        let doc = try document("Hello World")
        XCTAssertEqual(LyricsCaseCache().document(doc, trackKey: "a", textCase: .asWritten), doc)
    }

    func testUppercaseAppliesToLinesAndWordsWithTimingsKept() throws {
        let doc = try document("Hello World")
        let upper = LyricsCaseCache().document(doc, trackKey: "a", textCase: .upper)
        XCTAssertEqual(upper.lines[0].text, "HELLO WORLD")
        XCTAssertEqual(upper.lines[0].words.map(\.text), ["HELLO", "WORLD"])
        XCTAssertEqual(upper.lines[0].start, doc.lines[0].start)
        XCTAssertEqual(upper.lines[0].words.map(\.start), doc.lines[0].words.map(\.start))
        XCTAssertEqual(upper.lines.count, doc.lines.count)
    }

    func testCachedPerTrackAndCase() throws {
        let cache = LyricsCaseCache()
        let first = try document("one fish")
        let other = try document("two fish")
        let a = cache.document(first, trackKey: "t1", textCase: .upper)
        XCTAssertEqual(cache.document(first, trackKey: "t1", textCase: .upper), a)

        XCTAssertEqual(cache.document(first, trackKey: "t1", textCase: .lower).lines[0].text, "one fish", "switching case recomputes")
        XCTAssertEqual(cache.document(first, trackKey: "t1", textCase: .title).lines[0].text, "One Fish")
        XCTAssertEqual(cache.document(other, trackKey: "t2", textCase: .upper).lines[0].text, "TWO FISH", "a new track recomputes")
    }
}

// MARK: - Library model

final class BackgroundLibraryModelTests: XCTestCase {
    func testImportAddsItemsReportsBadFilesAndNotifies() throws {
        let source = tempDir("src")
        let png = writePNG((200, 60, 60), to: source.appendingPathComponent("red.png"))
        let text = source.appendingPathComponent("notes.txt")
        try "hi".write(to: text, atomically: true, encoding: .utf8)

        let model = BackgroundLibraryModel(library: BackgroundLibrary(directory: tempDir()))
        let builtIns = model.items.count
        var imported: BackgroundItem?
        model.onImported = { imported = $0 }

        model.importFiles([png, text])
        XCTAssertTrue(waitUntil { imported != nil && !model.isImporting })
        XCTAssertEqual(model.items.count, builtIns + 1)
        XCTAssertEqual(imported?.name, "red")
        XCTAssertTrue(model.message?.contains("notes.txt") == true, "the bad file is reported: \(model.message ?? "nil")")
        XCTAssertNotNil(model.thumbnail(for: try XCTUnwrap(imported)))
        XCTAssertNil(model.thumbnail(for: BackgroundLibrary.builtIns[0]), "built-ins are drawn from their stops")
    }

    func testDeleteRemovesAUserItemButNotABuiltIn() throws {
        let model = BackgroundLibraryModel(library: BackgroundLibrary(directory: tempDir()))
        var imported: BackgroundItem?
        model.onImported = { imported = $0 }
        model.importFiles([writePNG((20, 20, 200), to: tempDir("src").appendingPathComponent("b.png"))])
        XCTAssertTrue(waitUntil { imported != nil })
        let count = model.items.count

        model.delete(BackgroundLibrary.builtIns[0])
        XCTAssertEqual(model.items.count, count)
        model.delete(try XCTUnwrap(imported))
        XCTAssertEqual(model.items.count, count - 1)
    }

    func testSupportedExtensions() {
        for name in ["a.png", "a.JPG", "a.heic", "a.gif", "a.mov", "a.MP4", "a.m4v"] {
            XCTAssertTrue(BackgroundLibraryModel.isSupported(URL(fileURLWithPath: "/tmp/\(name)")), name)
        }
        for name in ["a.txt", "a.pdf", "a", "a.mkv"] {
            XCTAssertFalse(BackgroundLibraryModel.isSupported(URL(fileURLWithPath: "/tmp/\(name)")), name)
        }
    }
}

// MARK: - Background view

final class BackgroundViewTests: XCTestCase {
    func testGradientPublishesItsPalette() throws {
        let view = BackgroundView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        var seen: Palette?
        view.onPaletteChange = { seen = $0 }
        let sunset = try XCTUnwrap(BackgroundLibrary.builtIns.first { $0.id == "builtin.sunset" })
        view.show(sunset, library: BackgroundLibrary(directory: tempDir()))
        XCTAssertEqual(seen, sunset.palette)
        XCTAssertEqual(view.currentItem?.id, "builtin.sunset")
        view.dim = 0.5; view.blur = 12; view.fill = .fit   // none of these should misbehave
        view.layout()
    }

    func testImageIsDecodedOffThreadAndItsPaletteReported() throws {
        let dir = tempDir()
        let library = BackgroundLibrary(directory: dir)
        let item = try library.importFile(from: writePNG((30, 200, 60), to: tempDir("src").appendingPathComponent("green.png")))

        let view = BackgroundView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        var seen: Palette?
        view.onPaletteChange = { seen = $0 }
        view.show(item, library: library)
        XCTAssertTrue(waitUntil { seen != nil })
        XCTAssertGreaterThan(seen?.dominant.g ?? 0, 0.5, "a green picture gives green colors")
        XCTAssertEqual(view.currentItem?.id, item.id)
    }

    func testMissingFileFallsBackToTheFirstBuiltIn() {
        let view = BackgroundView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        var seen: Palette?
        view.onPaletteChange = { seen = $0 }
        let ghost = BackgroundItem(id: "user.ghost", name: "Ghost", kind: .image, fileName: "gone.png")
        view.show(ghost, library: BackgroundLibrary(directory: tempDir()))
        XCTAssertTrue(waitUntil { seen != nil })
        XCTAssertEqual(view.currentItem?.id, BackgroundLibrary.builtIns[0].id, "an empty window is never shown")
        let missingVideo = BackgroundItem(id: "user.ghostvideo", name: "Ghost", kind: .video, fileName: "gone.mov")
        view.show(missingVideo, library: BackgroundLibrary(directory: tempDir()))
        XCTAssertEqual(view.currentItem?.id, BackgroundLibrary.builtIns[0].id)
    }

    func testChoosingAnotherBackgroundIgnoresAStaleImageLoad() throws {
        let library = BackgroundLibrary(directory: tempDir())
        let image = try library.importFile(from: writePNG((200, 20, 20), to: tempDir("src").appendingPathComponent("r.png")))
        let view = BackgroundView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        var palettes: [Palette] = []
        view.onPaletteChange = { palettes.append($0) }
        view.show(image, library: library)
        let ocean = try XCTUnwrap(BackgroundLibrary.builtIns.first { $0.id == "builtin.ocean" })
        view.show(ocean, library: library)   // before the image finished decoding
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        XCTAssertEqual(view.currentItem?.id, "builtin.ocean")
        XCTAssertEqual(view.palette, ocean.palette, "the late image result must not overwrite the newer choice")
    }

    func testVideoPlaysSamplesItsColorsAndPausesOnDemand() throws {
        let library = BackgroundLibrary(directory: tempDir())
        let movie = tempDir("src").appendingPathComponent("flip.mov")
        try makeVideo(at: movie, a: (230, 30, 30), b: (30, 30, 230))
        let item = try library.importFile(from: movie)

        // A headless test window is never reported as visible (there is no active Space), and a view
        // that isn't visible rightly doesn't play, so visibility is stated directly here.
        let view = BackgroundView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        view.visibilityOverride = true
        var updates = 0
        view.onPaletteChange = { _ in updates += 1 }
        view.show(item, library: library)

        XCTAssertTrue(waitUntil(10) { view.videoSampleCount >= 1 }, "colors are sampled from the playing video")
        XCTAssertGreaterThan(updates, 1, "the cached palette first, then sampled ones")
        XCTAssertTrue(view.isPlayingVideo)

        view.setPlaybackAllowed(false)
        XCTAssertFalse(view.isPlayingVideo, "playback stops when the window says it is closing")
        view.setPlaybackAllowed(true)
        XCTAssertTrue(waitUntil(2) { view.isPlayingVideo })

        view.visibilityOverride = false
        XCTAssertFalse(view.isPlayingVideo, "and when the window can't be seen")
        let samples = view.videoSampleCount
        RunLoop.main.run(until: Date().addingTimeInterval(2))
        XCTAssertEqual(view.videoSampleCount, samples, "no sampling work while paused")
    }

    func testVideoSamplesFollowTheClipColor() throws {
        let library = BackgroundLibrary(directory: tempDir())
        let movie = tempDir("src").appendingPathComponent("blue.mov")
        try makeVideo(at: movie, a: (30, 30, 230), b: (30, 30, 230))
        let item = try library.importFile(from: movie)

        let view = BackgroundView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        view.visibilityOverride = true
        view.show(item, library: library)
        XCTAssertTrue(waitUntil(10) { view.videoSampleCount >= 1 })
        let sampled = try XCTUnwrap(view.palette)
        XCTAssertGreaterThan(sampled.dominant.b, sampled.dominant.r + 0.3, "a blue clip is sampled as blue: \(sampled.dominant)")
    }
}

// MARK: - Window controller

final class PlayerWindowControllerTests: XCTestCase {
    private func makeController(library: BackgroundLibrary? = nil) throws -> (PlayerWindowController, SettingsModel) {
        _ = NSApplication.shared
        let renderer = try metalRendererOrSkip()
        let model = SettingsModel(settings: AppSettings(), themeStore: ThemeStore(directory: tempDir("themes")))
        let controller = PlayerWindowController(
            renderer: renderer, model: model, session: LyricsSession(), capture: SystemAudioCapture(),
            library: library ?? BackgroundLibrary(directory: tempDir()))
        return (controller, model)
    }

    override func setUp() {
        // These tests create windows; keep them out of the user's saved window positions.
        setenv("LYRA_NO_FRAME_AUTOSAVE", "1", 1)
    }

    func testShowingAndClosingDoesNotCrashAndReleasesKeepAwake() throws {
        let (controller, _) = try makeController()
        controller.show()
        RunLoop.main.run(until: Date().addingTimeInterval(0.7))
        XCTAssertNotNil(controller.window)
        XCTAssertFalse(controller.isKeepingAwake, "nothing is playing, so nothing is held")

        controller.window?.close()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertFalse(controller.isVisible)
        XCTAssertFalse(controller.isKeepingAwake)
    }

    func testSettingsDriveTheWindow() throws {
        let (controller, model) = try makeController()
        controller.show()
        defer { controller.window?.close() }

        XCTAssertEqual(controller.window?.level, .normal)
        model.settings.player.keepOnTop = true
        XCTAssertEqual(controller.window?.level, .floating)
        model.settings.player.keepOnTop = false
        XCTAssertEqual(controller.window?.level, .normal)

        model.settings.player.backgroundID = "builtin.ocean"
        model.settings.player.dim = 0.6
        model.settings.player.blur = 10
        model.settings.player.fill = .fit
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))   // no crash while it applies
        XCTAssertTrue(controller.window?.collectionBehavior.contains(.fullScreenPrimary) == true, "native full screen is allowed")
        XCTAssertTrue(controller.window?.styleMask.contains(.resizable) == true)
    }

    func testImportedFilesAreSelectedThroughTheWindowPath() throws {
        let library = BackgroundLibrary(directory: tempDir())
        let (controller, model) = try makeController(library: library)
        controller.show()
        defer { controller.window?.close() }

        let png = writePNG((220, 120, 20), to: tempDir("src").appendingPathComponent("orange.png"))
        controller.importBackgrounds(from: [png])
        XCTAssertTrue(waitUntil { model.settings.player.backgroundID.hasPrefix("user.") }, "the new background is selected")
        XCTAssertEqual(library.userItems().count, 1)
        XCTAssertEqual(library.item(id: model.settings.player.backgroundID).name, "orange")
    }

    func testTheWindowDoesNotLeakAfterClose() throws {
        weak var weakController: PlayerWindowController?
        autoreleasepool {
            if let (controller, _) = try? makeController() {
                weakController = controller
                controller.show()
                RunLoop.main.run(until: Date().addingTimeInterval(0.3))
                controller.window?.close()
            }
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        // The timers and the event monitor hold the controller weakly, so it can go away.
        XCTAssertNil(weakController, "the controller should be released once nothing else holds it")
    }
}
