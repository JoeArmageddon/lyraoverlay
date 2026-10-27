import XCTest
import AVFoundation
import ImageIO
import UniformTypeIdentifiers
@testable import LyraCore

// MARK: - Helpers

private func tempDir(_ tag: String = "bg") -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("lyra-\(tag)-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// A `size`x`size` image: left half `left`, right half `right`.
private func makeImage(left: (UInt8, UInt8, UInt8), right: (UInt8, UInt8, UInt8), size: Int = 200) -> CGImage {
    var pixels = [UInt8](repeating: 255, count: size * size * 4)
    for y in 0..<size {
        for x in 0..<size {
            let c = x < size / 2 ? left : right
            let i = (y * size + x) * 4
            pixels[i] = c.0; pixels[i + 1] = c.1; pixels[i + 2] = c.2
        }
    }
    let provider = CGDataProvider(data: Data(pixels) as CFData)!
    return CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
                   space: CGColorSpace(name: CGColorSpace.sRGB)!,
                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                   provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
}

@discardableResult
private func writeImage(_ image: CGImage, to url: URL, type: UTType = .png) -> URL {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    XCTAssertTrue(CGImageDestinationFinalize(dest))
    return url
}

/// A short H.264 movie of one solid color.
private func makeVideo(at url: URL, color: (UInt8, UInt8, UInt8), seconds: Double = 2, size: Int = 64) throws {
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: size, AVVideoHeightKey: size,
    ])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: size, kCVPixelBufferHeightKey as String: size,
    ])
    writer.add(input)
    XCTAssertTrue(writer.startWriting())
    writer.startSession(atSourceTime: .zero)

    let fps = 10
    for frame in 0..<Int(seconds * Double(fps)) {
        while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.005) }
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, size, size, kCVPixelFormatType_32BGRA, nil, &buffer)
        let pb = try XCTUnwrap(buffer)
        CVPixelBufferLockBaseAddress(pb, [])
        let base = CVPixelBufferGetBaseAddress(pb)!.assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(pb)
        for y in 0..<size {
            for x in 0..<size {
                let p = base + y * stride + x * 4
                p[0] = color.2; p[1] = color.1; p[2] = color.0; p[3] = 255   // BGRA
            }
        }
        CVPixelBufferUnlockBaseAddress(pb, [])
        XCTAssertTrue(adaptor.append(pb, withPresentationTime: CMTime(value: Int64(frame), timescale: Int32(fps))))
    }
    input.markAsFinished()
    let done = DispatchSemaphore(value: 0)
    writer.finishWriting { done.signal() }
    done.wait()
    guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
}

private func sparseFile(_ url: URL, bytes: UInt64) throws {
    FileManager.default.createFile(atPath: url.path, contents: nil)
    let handle = try FileHandle(forWritingTo: url)
    try handle.truncate(atOffset: bytes)
    try handle.close()
}

private func isRedder(_ c: RGBA) -> Bool { c.r > c.b + 0.2 }
private func isBluer(_ c: RGBA) -> Bool { c.b > c.r + 0.2 }

// MARK: - Library

final class BackgroundLibraryTests: XCTestCase {
    func testBuiltInsAreStableAndColored() {
        let items = BackgroundLibrary.builtIns
        XCTAssertGreaterThanOrEqual(items.count, 6)
        XCTAssertEqual(Set(items.map(\.id)).count, items.count)
        for id in ["midnight", "aurora", "sunset", "ocean", "ember", "forest"] {
            XCTAssertTrue(items.contains { $0.id == "builtin.\(id)" }, id)
        }
        for item in items {
            XCTAssertEqual(item.kind, .gradient)
            XCTAssertTrue(item.isBuiltIn)
            XCTAssertGreaterThanOrEqual(item.stops.count, 2)
            XCTAssertNotNil(item.palette, item.name)
            XCTAssertNil(item.fileName)
        }
    }

    func testBuiltInPalettesMatchTheirColors() throws {
        func accent(_ id: String) throws -> RGBA { try XCTUnwrap(BackgroundLibrary.builtIns.first { $0.id == id }?.palette).accent }
        XCTAssertTrue(isRedder(try accent("builtin.sunset")), "sunset leans warm")
        XCTAssertTrue(isBluer(try accent("builtin.ocean")), "ocean leans blue")
    }

    func testEmptyLibraryListsBuiltInsAndUnknownIDFallsBack() {
        let library = BackgroundLibrary(directory: tempDir())
        XCTAssertEqual(library.all(), BackgroundLibrary.builtIns)
        XCTAssertEqual(library.item(id: "user.gone"), BackgroundLibrary.builtIns[0])
        XCTAssertEqual(library.item(id: "builtin.ocean").name, "Ocean")
    }

    func testImportImageCopiesThumbnailsAndPersists() throws {
        let dir = tempDir(), source = tempDir("src")
        let file = writeImage(makeImage(left: (230, 30, 30), right: (30, 30, 230)), to: source.appendingPathComponent("Red Blue.png"))
        let library = BackgroundLibrary(directory: dir)

        let item = try library.importFile(from: file)
        XCTAssertEqual(item.kind, .image)
        XCTAssertEqual(item.name, "Red Blue")
        XCTAssertTrue(item.id.hasPrefix("user."))
        XCTAssertFalse(item.isBuiltIn)

        let copy = try XCTUnwrap(library.fileURL(for: item))
        XCTAssertTrue(copy.path.hasPrefix(dir.path), "the file is copied into the library")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "the original is untouched")

        let thumb = try XCTUnwrap(library.thumbnailURL(for: item))
        let source2 = try XCTUnwrap(CGImageSourceCreateWithURL(thumb as CFURL, nil))
        let props = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source2, 0, nil) as? [CFString: Any])
        XCTAssertLessThanOrEqual(props[kCGImagePropertyPixelWidth] as? Int ?? 999, 320)

        // The palette sees both halves.
        let palette = try XCTUnwrap(item.palette)
        let colors = [palette.dominant, palette.accent, palette.secondary] + palette.swatches
        XCTAssertTrue(colors.contains(where: isRedder))
        XCTAssertTrue(colors.contains(where: isBluer))

        // A fresh instance over the same folder sees it.
        let again = BackgroundLibrary(directory: dir)
        XCTAssertEqual(again.userItems().map(\.id), [item.id])
        XCTAssertEqual(again.all().last?.id, item.id)
        XCTAssertEqual(again.item(id: item.id).name, "Red Blue")
    }

    func testImportJPEG() throws {
        let source = tempDir("src")
        let file = writeImage(makeImage(left: (20, 160, 60), right: (20, 160, 60)), to: source.appendingPathComponent("green.jpg"), type: .jpeg)
        XCTAssertEqual(try BackgroundLibrary(directory: tempDir()).importFile(from: file).kind, .image)
    }

    func testImportingTheSameNameTwiceNeverOverwrites() throws {
        let library = BackgroundLibrary(directory: tempDir()), source = tempDir("src")
        let file = writeImage(makeImage(left: (200, 0, 0), right: (0, 0, 200)), to: source.appendingPathComponent("same.png"))
        let a = try library.importFile(from: file), b = try library.importFile(from: file)
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertNotEqual(a.fileName, b.fileName)
        XCTAssertNotNil(library.fileURL(for: a))
        XCTAssertNotNil(library.fileURL(for: b))
        XCTAssertEqual(library.userItems().count, 2)
    }

    func testRejectsUnsupportedUnreadableAndUndecodableFiles() throws {
        let library = BackgroundLibrary(directory: tempDir()), source = tempDir("src")
        let text = source.appendingPathComponent("notes.txt")
        try "hello".write(to: text, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try library.importFile(from: text)) { XCTAssertEqual($0 as? BackgroundError, .unsupportedType("notes.txt")) }

        XCTAssertThrowsError(try library.importFile(from: source.appendingPathComponent("missing.png"))) {
            XCTAssertEqual($0 as? BackgroundError, .unreadable("missing.png"))
        }

        let fakeImage = source.appendingPathComponent("fake.png")
        try "not an image".write(to: fakeImage, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try library.importFile(from: fakeImage)) { XCTAssertEqual($0 as? BackgroundError, .notDecodable("fake.png")) }

        let fakeVideo = source.appendingPathComponent("fake.mp4")
        try Data(repeating: 7, count: 2048).write(to: fakeVideo)
        XCTAssertThrowsError(try library.importFile(from: fakeVideo)) { XCTAssertEqual($0 as? BackgroundError, .notDecodable("fake.mp4")) }

        XCTAssertTrue(library.userItems().isEmpty, "failed imports leave nothing behind")
        let files = (try? FileManager.default.contentsOfDirectory(atPath: library.directory.appendingPathComponent("Files").path)) ?? []
        XCTAssertTrue(files.isEmpty, "and no stray copies: \(files)")
    }

    func testSizeLimits() throws {
        let library = BackgroundLibrary(directory: tempDir()), source = tempDir("src")
        let bigImage = source.appendingPathComponent("huge.png")
        try sparseFile(bigImage, bytes: 101_000_000)
        XCTAssertThrowsError(try library.importFile(from: bigImage)) {
            guard case .tooLarge("huge.png", _)? = $0 as? BackgroundError else { return XCTFail("\($0)") }
        }
        let bigVideo = source.appendingPathComponent("huge.mov")
        try sparseFile(bigVideo, bytes: 2_100_000_000)
        XCTAssertThrowsError(try library.importFile(from: bigVideo)) {
            guard case .tooLarge("huge.mov", _)? = $0 as? BackgroundError else { return XCTFail("\($0)") }
        }
        XCTAssertTrue(library.userItems().isEmpty)
    }

    func testImportVideo() throws {
        let library = BackgroundLibrary(directory: tempDir()), source = tempDir("src")
        let movie = source.appendingPathComponent("clip.mov")
        try makeVideo(at: movie, color: (30, 60, 220))

        let item = try library.importFile(from: movie)
        XCTAssertEqual(item.kind, .video)
        XCTAssertNotNil(library.fileURL(for: item))
        XCTAssertNotNil(library.thumbnailURL(for: item))
        let palette = try XCTUnwrap(item.palette)
        XCTAssertTrue(isBluer(palette.dominant), "a blue clip gives a blue palette, got \(palette.dominant)")
    }

    func testDeleteRemovesFilesAndIndexEntry() throws {
        let library = BackgroundLibrary(directory: tempDir()), source = tempDir("src")
        let file = writeImage(makeImage(left: (200, 0, 0), right: (0, 0, 200)), to: source.appendingPathComponent("d.png"))
        let item = try library.importFile(from: file)
        let copy = try XCTUnwrap(library.fileURL(for: item)), thumb = try XCTUnwrap(library.thumbnailURL(for: item))

        XCTAssertTrue(library.delete(id: item.id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: copy.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: thumb.path))
        XCTAssertTrue(library.userItems().isEmpty)
        XCTAssertFalse(library.delete(id: item.id), "already gone")
    }

    func testBuiltInsCannotBeDeleted() {
        let library = BackgroundLibrary(directory: tempDir())
        XCTAssertFalse(library.delete(id: "builtin.midnight"))
        XCTAssertEqual(library.all(), BackgroundLibrary.builtIns)
    }

    func testCorruptIndexIsAnEmptyLibraryAndImportRecovers() throws {
        let dir = tempDir()
        try Data("{ this is not json".utf8).write(to: dir.appendingPathComponent("index.json"))
        let library = BackgroundLibrary(directory: dir)
        XCTAssertTrue(library.userItems().isEmpty)
        XCTAssertEqual(library.all(), BackgroundLibrary.builtIns)

        let file = writeImage(makeImage(left: (0, 200, 0), right: (0, 100, 0)), to: tempDir("src").appendingPathComponent("ok.png"))
        let item = try library.importFile(from: file)
        XCTAssertEqual(BackgroundLibrary(directory: dir).userItems().map(\.id), [item.id])
    }

    func testMissingFilesGiveNilURLs() {
        let library = BackgroundLibrary(directory: tempDir())
        let ghost = BackgroundItem(id: "user.ghost", name: "Ghost", kind: .image, fileName: "ghost.png")
        XCTAssertNil(library.fileURL(for: ghost))
        XCTAssertNil(library.thumbnailURL(for: ghost))
        XCTAssertNil(library.thumbnailURL(for: BackgroundLibrary.builtIns[0]))
        XCTAssertNil(library.fileURL(for: BackgroundLibrary.builtIns[0]))
    }
}

final class BackgroundItemTests: XCTestCase {
    func testTolerantDecoding() throws {
        let item = try JSONDecoder().decode(BackgroundItem.self, from: Data(#"{"id": "user.x", "kind": "nonsense"}"#.utf8))
        XCTAssertEqual(item.id, "user.x")
        XCTAssertEqual(item.name, "user.x")
        XCTAssertEqual(item.kind, .image)
        XCTAssertTrue(item.stops.isEmpty)
        XCTAssertNil(item.palette)
    }

    func testIdentityIsRequired() {
        XCTAssertThrowsError(try JSONDecoder().decode(BackgroundItem.self, from: Data(#"{"name": "No id"}"#.utf8)))
    }

    func testRoundTrip() throws {
        let item = BackgroundLibrary.builtIns[1]
        let data = try JSONEncoder().encode(item)
        XCTAssertEqual(try JSONDecoder().decode(BackgroundItem.self, from: data), item)
    }

    func testGradientColorInterpolation() {
        let stops = [RGBA(0, 0, 0), RGBA(1, 1, 1)]
        XCTAssertEqual(BackgroundItem.color(at: 0, in: stops).r, 0, accuracy: 1e-6)
        XCTAssertEqual(BackgroundItem.color(at: 0.5, in: stops).r, 0.5, accuracy: 1e-6)
        XCTAssertEqual(BackgroundItem.color(at: 2, in: stops).r, 1, accuracy: 1e-6, "clamped")
    }

    func testPlayerSettingsDecodeTolerantly() throws {
        let s = try JSONDecoder().decode(PlayerSettings.self, from: Data(#"{"dim": 0.5, "blur": "x"}"#.utf8))
        XCTAssertEqual(s.dim, 0.5)
        XCTAssertEqual(s.blur, PlayerSettings().blur)
        XCTAssertEqual(s.backgroundID, "builtin.midnight")
        XCTAssertEqual(try JSONDecoder().decode(PlayerSettings.self, from: Data("{}".utf8)), PlayerSettings())
    }
}

// MARK: - Smoother

final class PaletteSmootherTests: XCTestCase {
    private func palette(_ c: RGBA) -> Palette { Palette(dominant: c, accent: c, secondary: c, swatches: [c], isDark: true) }
    private let red = RGBA(1, 0, 0), blue = RGBA(0, 0, 1)

    func testFirstUpdateReturnsTheTarget() {
        var s = PaletteSmoother()
        XCTAssertEqual(s.update(target: palette(red), dt: 0.016), palette(red))
    }

    func testApproachesMonotonicallyWithoutOvershoot() {
        var s = PaletteSmoother(timeConstant: 0.5)
        _ = s.update(target: palette(red), dt: 0)
        var last: Float = 0
        for _ in 0..<200 {
            let b = s.update(target: palette(blue), dt: 0.016).accent
            XCTAssertGreaterThanOrEqual(b.b, last - 1e-6, "blue only increases")
            XCTAssertLessThanOrEqual(b.b, 1 + 1e-6, "never past the target")
            XCTAssertGreaterThanOrEqual(b.r, -1e-6)
            last = b.b
        }
    }

    func testConverges() {
        var s = PaletteSmoother(timeConstant: 0.5)
        _ = s.update(target: palette(red), dt: 0)
        var p = palette(red)
        for _ in 0..<700 { p = s.update(target: palette(blue), dt: 0.016) }   // about 11 s
        XCTAssertEqual(p.accent.b, 1, accuracy: 1e-3)
        XCTAssertEqual(p.dominant.r, 0, accuracy: 1e-3)
    }

    func testResultDoesNotDependOnHowTimeIsSplit() {
        var one = PaletteSmoother(), many = PaletteSmoother()
        _ = one.update(target: palette(red), dt: 0)
        _ = many.update(target: palette(red), dt: 0)
        let a = one.update(target: palette(blue), dt: 1.0).accent
        var b = RGBA.white
        for _ in 0..<10 { b = many.update(target: palette(blue), dt: 0.1).accent }
        XCTAssertEqual(a.b, b.b, accuracy: 1e-4)
        XCTAssertEqual(a.r, b.r, accuracy: 1e-4)
    }

    func testZeroTimeChangesNothingAndResetRestarts() {
        var s = PaletteSmoother()
        _ = s.update(target: palette(red), dt: 0)
        XCTAssertEqual(s.update(target: palette(blue), dt: 0).accent, red)
        s.reset()
        XCTAssertEqual(s.update(target: palette(blue), dt: 0.01).accent, blue, "after a reset the next target is taken as is")
    }

    func testGlideTakesAboutAFewTimeConstants() {
        var s = PaletteSmoother(timeConstant: 0.5)
        _ = s.update(target: palette(red), dt: 0)
        let afterOne = s.update(target: palette(blue), dt: 1.0).accent.b   // two time constants
        XCTAssertEqual(afterOne, 1 - Float(exp(-2.0)), accuracy: 1e-3)
    }
}

// MARK: - Keep awake

private final class FakeAssertion: PowerAssertion {
    var creates = 0, releases = 0
    var succeeds = true
    private(set) var held = false
    func create(reason: String) -> Bool {
        creates += 1
        held = succeeds
        return succeeds
    }
    func release() { releases += 1; held = false }
}

final class KeepAwakeTests: XCTestCase {
    func testPolicyTruthTable() {
        for enabled in [false, true] { for visible in [false, true] { for playing in [false, true] {
            XCTAssertEqual(KeepAwakePolicy.shouldBeAwake(enabled: enabled, windowVisible: visible, playing: playing),
                           enabled && visible && playing)
        } } }
    }

    func testCreatesOnceAndReleasesOnceAcrossManyUpdates() {
        let fake = FakeAssertion()
        let awake = KeepAwake(assertion: fake)
        for _ in 0..<5 { awake.update(enabled: true, windowVisible: true, playing: true) }
        XCTAssertTrue(awake.isActive)
        XCTAssertEqual(fake.creates, 1)
        XCTAssertEqual(fake.releases, 0)

        for _ in 0..<5 { awake.update(enabled: true, windowVisible: true, playing: false) }
        XCTAssertFalse(awake.isActive)
        XCTAssertEqual(fake.releases, 1)
        XCTAssertEqual(fake.creates, 1)
    }

    func testEachConditionAloneReleases() {
        for change in 0..<3 {
            let fake = FakeAssertion()
            let awake = KeepAwake(assertion: fake)
            awake.update(enabled: true, windowVisible: true, playing: true)
            awake.update(enabled: change != 0, windowVisible: change != 1, playing: change != 2)
            XCTAssertFalse(awake.isActive, "condition \(change)")
            XCTAssertEqual(fake.releases, 1)
        }
    }

    func testReacquiresAfterAReleaseAndRetriesAfterAFailure() {
        let fake = FakeAssertion()
        fake.succeeds = false
        let awake = KeepAwake(assertion: fake)
        awake.update(enabled: true, windowVisible: true, playing: true)
        XCTAssertFalse(awake.isActive, "the system refused")
        fake.succeeds = true
        awake.update(enabled: true, windowVisible: true, playing: true)
        XCTAssertTrue(awake.isActive, "retried on the next update")
        XCTAssertEqual(fake.creates, 2)

        awake.update(enabled: false, windowVisible: true, playing: true)
        awake.update(enabled: true, windowVisible: true, playing: true)
        XCTAssertEqual(fake.creates, 3)
        XCTAssertEqual(fake.releases, 1)
    }

    func testNeverCreatesWhileDisabled() {
        let fake = FakeAssertion()
        let awake = KeepAwake(assertion: fake)
        awake.update(enabled: false, windowVisible: true, playing: true)
        XCTAssertEqual(fake.creates, 0)
        XCTAssertEqual(fake.releases, 0)
    }

    func testReleaseNowAndDeinitRelease() {
        let fake = FakeAssertion()
        var awake: KeepAwake? = KeepAwake(assertion: fake)
        awake?.update(enabled: true, windowVisible: true, playing: true)
        awake?.releaseNow()
        XCTAssertFalse(awake?.isActive ?? true)
        XCTAssertEqual(fake.releases, 1)
        awake?.releaseNow()
        XCTAssertEqual(fake.releases, 1, "nothing left to release")

        awake?.update(enabled: true, windowVisible: true, playing: true)
        awake = nil
        XCTAssertEqual(fake.releases, 2, "dropping it releases a held assertion")
    }

    func testTheRealAssertionCreatesAndReleases() {
        let real = IOKitPowerAssertion()
        XCTAssertTrue(real.create(reason: "Lyra unit test"))
        XCTAssertTrue(real.create(reason: "Lyra unit test"), "creating again keeps the one assertion")
        real.release()
        real.release()   // harmless
    }
}

// MARK: - Player control

final class PlayerControlTests: XCTestCase {
    func testScriptsUseTheRightVerbAndATimeout() {
        let cases: [(PlayerCommand, String)] = [(.playPause, "playpause"), (.next, "next track"), (.previous, "previous track")]
        for (command, verb) in cases {
            for (player, app) in [(PlayerKind.spotify, "Spotify"), (.appleMusic, "Music")] {
                let script = PlayerControl.script(for: command, player: player)
                XCTAssertTrue(script.contains("tell application \"\(app)\" to \(verb)"), script)
                XCTAssertTrue(script.hasPrefix("with timeout of 3 seconds"), script)
                XCTAssertTrue(script.hasSuffix("end timeout"), script)
            }
        }
    }

    /// Compiling needs the app's dictionary, so it only runs where the app is installed. Nothing is executed.
    func testControlScriptsCompile() throws {
        for (player, bundleID) in [(PlayerKind.spotify, "com.spotify.client"), (.appleMusic, "com.apple.Music")] {
            guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil else { continue }
            for command in [PlayerCommand.playPause, .next, .previous] {
                var error: NSDictionary?
                let script = try XCTUnwrap(NSAppleScript(source: PlayerControl.script(for: command, player: player)))
                XCTAssertTrue(script.compileAndReturnError(&error), "\(player) \(command): \(String(describing: error))")
            }
        }
    }

    func testSendingToAnAppThatIsNotRunningDoesNothing() async throws {
        // Only meaningful (and safe) when the app is closed: otherwise this would really pause the user's music.
        try XCTSkipIf(!NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").isEmpty, "Spotify is running")
        let sent = await PlayerControl.send(.playPause, to: .spotify)
        XCTAssertFalse(sent)
    }
}
