import XCTest
import LyraCore
@testable import LyraRender

final class FontTests: XCTestCase {
    private let scale: CGFloat = 1

    private func raster(_ text: String, _ font: FontSpec) throws -> RasterizedText {
        try XCTUnwrap(TextRasterizer.rasterize(text, font: font, scale: scale))
    }

    /// Columns (left, right) of the first and last pixel with visible ink.
    private func inkExtent(_ r: RasterizedText) -> (left: Int, right: Int)? {
        var left: Int?, right: Int?
        for x in 0..<r.pixelWidth {
            var any = false
            for y in 0..<r.pixelHeight where r.pixels[(y * r.pixelWidth + x) * 4 + 3] > 24 { any = true; break }
            if any { if left == nil { left = x }; right = x }
        }
        guard let left, let right else { return nil }
        return (left, right)
    }

    // MARK: - Tracking

    func testTrackingWidensMeasuredTextByOneGapPerCharacterGap() {
        let m = CoreTextMeasurer()
        let plain = FontSpec(size: 60)
        let spaced = FontSpec(size: 60, tracking: 0.2)
        let text = "Hello"
        // Four gaps between five letters; the trailing gap is excluded on purpose.
        XCTAssertEqual(m.width(of: text, font: spaced) - m.width(of: text, font: plain), 4 * 0.2 * 60, accuracy: 0.75)
    }

    func testNegativeTrackingNarrows() {
        let m = CoreTextMeasurer()
        XCTAssertLessThan(m.width(of: "Hello", font: FontSpec(size: 60, tracking: -0.05)), m.width(of: "Hello", font: FontSpec(size: 60)))
    }

    func testSingleCharacterIgnoresTracking() {
        let m = CoreTextMeasurer()
        XCTAssertEqual(m.width(of: "H", font: FontSpec(size: 60, tracking: 0.5)), m.width(of: "H", font: FontSpec(size: 60)), accuracy: 0.01)
    }

    func testTrackingChangesTheRasterizedBitmap() throws {
        let tight = try raster("Hello", FontSpec(size: 60, weight: 0.4))
        let wide = try raster("Hello", FontSpec(size: 60, weight: 0.4, tracking: 0.2))
        XCTAssertGreaterThan(wide.pixelWidth, tight.pixelWidth + 30)
    }

    func testRasterizedTextBoundsMatchTheMeasuredWidth() throws {
        let font = FontSpec(size: 60, weight: 0.4, tracking: 0.15)
        let r = try raster("Hello world", font)
        let drawn = CGFloat(r.textEndU - r.textStartU) * CGFloat(r.pixelWidth) / scale
        XCTAssertEqual(drawn, CoreTextMeasurer().width(of: "Hello world", font: font), accuracy: 1.5)
    }

    func testCenteredTextInkIsSymmetricEvenWithWideTracking() throws {
        // Symmetric glyphs: any left/right imbalance comes from the layout, not the letters.
        for tracking in [0.0, 0.15, 0.4] {
            let r = try raster("OHO", FontSpec(size: 80, weight: 0.4, tracking: tracking))
            let extent = try XCTUnwrap(inkExtent(r))
            let leftMargin = extent.left
            let rightMargin = r.pixelWidth - 1 - extent.right
            XCTAssertEqual(leftMargin, rightMargin, accuracy: 4, "tracking \(tracking): margins \(leftMargin) vs \(rightMargin)")
        }
    }

    func testSungWipeRangeStaysInsideTheBitmapWithTracking() throws {
        let r = try raster("Wipe", FontSpec(size: 50, tracking: 0.3))
        XCTAssertGreaterThan(r.textStartU, 0)
        XCTAssertLessThan(r.textEndU, 1)
        XCTAssertGreaterThan(r.textEndU, r.textStartU)
    }

    // MARK: - Italic

    func testItalicChangesPixelsForAFamilyWithAnItalicFace() throws {
        try XCTSkipUnless(FontCatalog.isInstalled("Helvetica Neue"))
        let upright = try raster("Slant", FontSpec(family: "Helvetica Neue", size: 60))
        let italic = try raster("Slant", FontSpec(family: "Helvetica Neue", size: 60, italic: true))
        XCTAssertTrue(upright.pixels != italic.pixels || upright.pixelWidth != italic.pixelWidth)
    }

    func testItalicOnTheSystemFontChangesTheOutput() throws {
        let upright = try raster("Slant", FontSpec(size: 60, weight: 0.4))
        let italic = try raster("Slant", FontSpec(size: 60, weight: 0.4, italic: true))
        XCTAssertTrue(upright.pixels != italic.pixels || upright.pixelWidth != italic.pixelWidth)
    }

    func testItalicNeverFailsForFamiliesWithoutOne() throws {
        for family in ["Apple Symbols", "Zapfino", "Definitely Not A Font"] {
            let r = try raster("Text", FontSpec(family: family, size: 40, italic: true))
            XCTAssertGreaterThan(r.pixelWidth, 10, family)
            XCTAssertGreaterThan(CoreTextMeasurer().width(of: "Text", font: FontSpec(family: family, size: 40, italic: true)), 0, family)
        }
    }

    // MARK: - Texture cache keys

    func testCacheKeysSeparateTrackingAndItalic() throws {
        let renderer = try metalRendererOrSkip()
        let cache = renderer.textures
        let base = FontSpec(size: 40)
        _ = cache.texture(for: "Key", font: base, scale: 1)
        let afterBase = cache.count
        _ = cache.texture(for: "Key", font: base, scale: 1)
        XCTAssertEqual(cache.count, afterBase, "same font reuses its texture")
        _ = cache.texture(for: "Key", font: FontSpec(size: 40, tracking: 0.1), scale: 1)
        XCTAssertEqual(cache.count, afterBase + 1, "tracking gets its own texture")
        _ = cache.texture(for: "Key", font: FontSpec(size: 40, italic: true), scale: 1)
        XCTAssertEqual(cache.count, afterBase + 2, "italic gets its own texture")
    }

    func testMeasurerCacheSeparatesTrackingAndItalic() {
        let m = CoreTextMeasurer()
        let a = m.width(of: "Cache", font: FontSpec(size: 50))
        let b = m.width(of: "Cache", font: FontSpec(size: 50, tracking: 0.2))
        let c = m.width(of: "Cache", font: FontSpec(size: 50, tracking: 0.2))
        XCTAssertGreaterThan(b, a)
        XCTAssertEqual(b, c)
    }

    // MARK: - Catalog

    func testFamiliesStartWithSystemAndAreCleanAndUnique() {
        let families = FontCatalog.families()
        XCTAssertEqual(families.first, "System")
        XCTAssertEqual(families.count, Set(families).count, "no duplicates")
        XCTAssertFalse(families.contains { $0.hasPrefix(".") }, "no hidden system families")
        XCTAssertGreaterThan(families.count, 10)
        let rest = Array(families.dropFirst())
        XCTAssertEqual(rest, rest.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
    }

    func testIsInstalled() {
        XCTAssertTrue(FontCatalog.isInstalled("System"))
        XCTAssertTrue(FontCatalog.isInstalled("Helvetica Neue"))
        XCTAssertFalse(FontCatalog.isInstalled("Definitely Not A Font"))
    }

    func testEveryListedFamilyCanBeResolvedAndMeasured() {
        let m = CoreTextMeasurer()
        // Resolving must never crash. A symbol-only family may measure plain letters as
        // zero, so require nearly all of them (not every one) to have a width.
        let sample = Array(FontCatalog.families().prefix(40))
        let measurable = sample.filter { m.width(of: "Abc", font: FontSpec(family: $0, size: 30)) > 0 }
        XCTAssertGreaterThanOrEqual(measurable.count, sample.count * 9 / 10, "unmeasurable: \(Set(sample).subtracting(measurable))")
    }

    // MARK: - Import

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lyra-fonts-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A real, small font file from the system to import from.
    private func installedFontFile() -> URL? {
        for root in ["/System/Library/Fonts/Supplemental", "/System/Library/Fonts", "/Library/Fonts"] {
            let files = (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []
            if let name = files.sorted().first(where: { $0.lowercased().hasSuffix(".ttf") }) {
                return URL(fileURLWithPath: root).appendingPathComponent(name)
            }
        }
        return nil
    }

    func testImportRejectsATextFileWithAClearError() throws {
        let temp = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        FontCatalog.directoryOverride = temp.appendingPathComponent("UserFonts")
        defer { FontCatalog.directoryOverride = nil }

        let notes = temp.appendingPathComponent("notes.txt")
        try Data("hello".utf8).write(to: notes)
        XCTAssertThrowsError(try FontCatalog.importFont(from: notes)) { error in
            XCTAssertEqual(error as? FontImportError, .unsupportedType("notes.txt"))
            XCTAssertTrue((error as? LocalizedError)?.errorDescription?.contains("notes.txt") == true)
        }

        // Right extension, wrong contents.
        let fake = temp.appendingPathComponent("fake.ttf")
        try Data("not a font at all".utf8).write(to: fake)
        XCTAssertThrowsError(try FontCatalog.importFont(from: fake)) { error in
            XCTAssertEqual(error as? FontImportError, .notAFont("fake.ttf"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: FontCatalog.userFontsDirectory.path), "nothing is copied for a rejected file")

        XCTAssertThrowsError(try FontCatalog.importFont(from: temp.appendingPathComponent("missing.ttf")))
    }

    func testImportCopiesAndRegistersARealFont() throws {
        let temp = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        FontCatalog.directoryOverride = temp.appendingPathComponent("UserFonts")
        defer { FontCatalog.directoryOverride = nil }

        // A font macOS has never seen (a renamed copy of a Lyra font), as a user's Downloads file would be.
        let download = try TestFont.makeUnique(in: temp.appendingPathComponent("Downloads"))
        let families = try FontCatalog.importFont(from: download.url)
        XCTAssertEqual(families, [download.family])
        XCTAssertTrue(FileManager.default.fileExists(atPath: FontCatalog.userFontsDirectory.appendingPathComponent(download.url.lastPathComponent).path))
        XCTAssertTrue(families.allSatisfy(FontCatalog.isInstalled))
        XCTAssertTrue(FontCatalog.isInstalled(download.postScript))

        // Importing the same font again is refused as a duplicate and never copies a second file.
        XCTAssertThrowsError(try FontCatalog.importFont(from: download.url)) { error in
            guard case .duplicate(let name, let reason)? = error as? FontImportError else { return XCTFail("\(error)") }
            XCTAssertEqual(name, download.url.lastPathComponent)
            XCTAssertTrue(reason.contains("already added"), reason)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: FontCatalog.userFontsDirectory.path).count, 1)
    }

    func testRegisterUserFontsToleratesAMissingOrEmptyFolder() throws {
        let temp = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        FontCatalog.directoryOverride = temp.appendingPathComponent("DoesNotExist")
        defer { FontCatalog.directoryOverride = nil }
        FontCatalog.registerUserFonts()   // must not crash or throw

        try FileManager.default.createDirectory(at: FontCatalog.userFontsDirectory, withIntermediateDirectories: true)
        try Data("junk".utf8).write(to: FontCatalog.userFontsDirectory.appendingPathComponent("junk.ttf"))
        FontCatalog.registerUserFonts()   // a corrupt file in the folder is ignored
    }

    // MARK: - Visual sanity

    /// Writes a sheet to the temp folder so a human can look at tracking, italic and case together.
    func testWritesASanitySheet() throws {
        let renderer = try metalRendererOrSkip()
        let size = CGSize(width: 900, height: 520)
        let rows: [(String, FontSpec)] = [
            ("Neutral sample line", FontSpec(size: 52, weight: 0.4)),
            ("Wide tracking sample", FontSpec(size: 52, weight: 0.4, tracking: 0.18)),
            ("Tight tracking sample", FontSpec(size: 52, weight: 0.4, tracking: -0.04)),
            ("Italic helvetica", FontSpec(family: "Helvetica Neue", size: 52, weight: 0.4, italic: true)),
            (TextCase.upper.apply("Uppercase spaced"), FontSpec(size: 46, weight: 0.4, tracking: 0.14)),
        ]
        let items = rows.enumerated().map { n, row in
            DrawItem(text: row.0, font: row.1, center: CGPoint(x: size.width / 2, y: 60 + CGFloat(n) * 95),
                     size: CGSize(width: 800, height: 80), baseColor: RGBA(1, 1, 1, 0.4), highlightColor: .white,
                     glowColor: RGBA(0.5, 0.7, 1), glow: 0.4, progress: 0.55, opacity: 1, shadow: 0.4)
        }
        let image = try XCTUnwrap(renderer.renderOffscreen(items, size: size, scale: 1))

        let ctx = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue))
        ctx.setFillColor(CGColor(red: 0.1, green: 0.11, blue: 0.16, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let out = try XCTUnwrap(ctx.makeImage())

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lyra-font-sanity.png")
        XCTAssertTrue(SnapshotSheet.writePNG(out, to: url))
    }
}
