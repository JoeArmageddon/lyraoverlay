import XCTest
import CoreText
import LyraCore
@testable import LyraRender

/// The generated Lyra Originals in the project's `Fonts/` folder, checked as a user of them would:
/// through CoreText and through Lyra's own resolver.
final class OriginalFontTests: XCTestCase {
    /// <project>/Fonts, found from this file's path (LyraApp/Tests/LyraRenderTests/<file>).
    private let fontsDir: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fonts", isDirectory: true)

    private var originals: [FeaturedFont] { FontCatalog.originals }

    private func url(_ font: FeaturedFont) -> URL { fontsDir.appendingPathComponent(font.id + ".ttf") }

    private func descriptor(_ font: FeaturedFont) throws -> CTFontDescriptor {
        let list = try XCTUnwrap(CTFontManagerCreateFontDescriptorsFromURL(url(font) as CFURL) as? [CTFontDescriptor], font.name)
        return try XCTUnwrap(list.first)
    }

    override func setUp() {
        super.setUp()
        FontCatalog.bundledDirectoryOverride = nil
        FontCatalog.registerBundledFonts()
    }

    /// The generated Lyra Originals are exactly these eight. A ninth generated font is a deliberate
    /// change: add it here, to `FontCatalog.originals` and to Tools/FontFactory together.
    static let knownOriginalIDs = ["LyraForge-Regular", "LyraBlade-Regular", "LyraStencilOps-Regular", "LyraCircuit-Regular",
                                   "LyraNeonTube-Regular", "LyraThorn-Regular", "LyraMonolineRound-Regular", "LyraPixel-Regular"]

    func testTheGeneratedOriginalsAreExactlyTheEightKnownIDs() {
        XCTAssertEqual(FontCatalog.originals.map(\.id), Self.knownOriginalIDs)
        XCTAssertEqual(FontCatalog.originalIDs, Self.knownOriginalIDs)
        XCTAssertTrue(FontCatalog.originals.allSatisfy { $0.category == .originals })
        XCTAssertTrue(Set(FontCatalog.originalIDs).isDisjoint(with: FontCatalog.handDrawn.map(\.id)), "a font is either an original or hand-drawn")
    }

    // MARK: - Files

    func testTheFilesAndDocsArePresent() {
        let fm = FileManager.default
        XCTAssertEqual(originals.map(\.id), Self.knownOriginalIDs)
        for font in originals { XCTAssertTrue(fm.fileExists(atPath: url(font).path), "\(font.id).ttf is missing from Fonts/") }
        XCTAssertTrue(fm.fileExists(atPath: fontsDir.appendingPathComponent("LICENSE.txt").path))
        XCTAssertTrue(fm.fileExists(atPath: fontsDir.appendingPathComponent("README.md").path))
        for font in originals {
            let specimen = fontsDir.appendingPathComponent("specimens/" + font.name.replacingOccurrences(of: "Lyra ", with: "").replacingOccurrences(of: " ", with: "") + ".png")
            XCTAssertTrue(fm.fileExists(atPath: specimen.path), "no specimen for \(font.name)")
        }
    }

    func testLicenseIsStatedInTheFilesAndInTheFonts() throws {
        let license = try String(contentsOf: fontsDir.appendingPathComponent("LICENSE.txt"), encoding: .utf8)
        XCTAssertTrue(license.contains("SIL Open Font License"))
        XCTAssertTrue(license.contains("2026 Lyra project"))
        for font in originals {
            let ct = CTFontCreateWithFontDescriptor(try descriptor(font), 20, nil)
            let copyright = CTFontCopyName(ct, kCTFontCopyrightNameKey) as String?
            XCTAssertTrue(copyright?.contains("Lyra project") == true, "\(font.name) copyright: \(copyright ?? "none")")
            let licenseText = CTFontCopyName(ct, kCTFontLicenseNameKey) as String?
            XCTAssertTrue(licenseText?.contains("SIL Open Font License") == true, "\(font.name) license: \(licenseText ?? "none")")
        }
    }

    // MARK: - Loading and names

    func testEveryOriginalLoadsWithItsOwnUniqueNames() throws {
        var postScript = Set<String>(), families = Set<String>()
        for font in originals {
            let d = try descriptor(font)
            let ps = try XCTUnwrap(CTFontDescriptorCopyAttribute(d, kCTFontNameAttribute) as? String)
            let family = try XCTUnwrap(CTFontDescriptorCopyAttribute(d, kCTFontFamilyNameAttribute) as? String)
            XCTAssertEqual(ps, font.id)
            XCTAssertEqual(family, font.name)
            XCTAssertTrue(postScript.insert(ps).inserted, "duplicate PostScript name \(ps)")
            XCTAssertTrue(families.insert(family).inserted, "duplicate family \(family)")
        }
    }

    // MARK: - Coverage

    private let required: [Character] = {
        var c: [Character] = []
        for u in UnicodeScalar("A").value...UnicodeScalar("Z").value { c.append(Character(UnicodeScalar(u)!)) }
        for u in UnicodeScalar("a").value...UnicodeScalar("z").value { c.append(Character(UnicodeScalar(u)!)) }
        c += Array("0123456789.,!?'\"-:;&()/#@%+=$*_~^<>[]{}|\\ ")
        c += Array("\u{2026}\u{2013}\u{2014}\u{2018}\u{2019}\u{201C}\u{201D}\u{00A1}\u{00BF}\u{00B0}")
        c += Array("áàâäãåéèêëíìîïóòôöõúùûüñçýÿÁÀÂÄÃÅÉÈÊËÍÌÎÏÓÒÔÖÕÚÙÛÜÑÇÝŸ")
        return c
    }()

    func testEveryOriginalCoversTheRequiredCharacters() throws {
        for font in originals {
            let ct = CTFontCreateWithFontDescriptor(try descriptor(font), 100, nil)
            for ch in required {
                let units = Array(String(ch).utf16)
                var glyphs = [CGGlyph](repeating: 0, count: units.count)
                XCTAssertTrue(CTFontGetGlyphsForCharacters(ct, units, &glyphs, units.count), "\(font.name) has no glyph for \(ch)")
            }
        }
    }

    // MARK: - Metrics and outlines

    func testMetricsAreSane() throws {
        for font in originals {
            let ct = CTFontCreateWithFontDescriptor(try descriptor(font), 100, nil)
            XCTAssertEqual(CTFontGetUnitsPerEm(ct), 1000)
            XCTAssertEqual(CTFontGetAscent(ct), 80, accuracy: 0.5, font.name)
            XCTAssertEqual(CTFontGetDescent(ct), 20, accuracy: 0.5, font.name)
            XCTAssertEqual(CTFontGetLeading(ct), 0, accuracy: 0.5, font.name)
            XCTAssertEqual(CTFontGetCapHeight(ct), 70, accuracy: 0.5, font.name)
            let xHeight = CTFontGetXHeight(ct)
            XCTAssertTrue(xHeight > 40 && xHeight <= 70.5, "\(font.name) x-height \(xHeight)")
        }
    }

    func testLettersAndDigitsHaveOutlinesAndPositiveAdvances() throws {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
        for font in originals {
            let ct = CTFontCreateWithFontDescriptor(try descriptor(font), 100, nil)
            for ch in chars {
                var unit = UniChar(ch.unicodeScalars.first!.value)
                var glyph = CGGlyph()
                XCTAssertTrue(CTFontGetGlyphsForCharacters(ct, &unit, &glyph, 1))
                let path = try XCTUnwrap(CTFontCreatePathForGlyph(ct, glyph, nil), "\(font.name) \(ch) has no outline")
                XCTAssertFalse(path.boundingBoxOfPath.isEmpty, "\(font.name) \(ch) draws nothing")
                var advance = CGSize.zero
                CTFontGetAdvancesForGlyphs(ct, .horizontal, &glyph, &advance, 1)
                XCTAssertGreaterThan(advance.width, 0, "\(font.name) \(ch) advance")
            }
        }
    }

    func testGlyphBoundingBoxesStayInASaneBox() throws {
        for font in originals {
            let ct = CTFontCreateWithFontDescriptor(try descriptor(font), 100, nil)
            for ch in required where ch != " " {
                var unit = UniChar(ch.unicodeScalars.first!.value)
                var glyph = CGGlyph()
                CTFontGetGlyphsForCharacters(ct, &unit, &glyph, 1)
                guard let path = CTFontCreatePathForGlyph(ct, glyph, nil) else { continue }
                var advance = CGSize.zero
                CTFontGetAdvancesForGlyphs(ct, .horizontal, &glyph, &advance, 1)
                let b = path.boundingBoxOfPath
                XCTAssertGreaterThan(b.minX, -10, "\(font.name) \(ch) starts left of its origin")
                XCTAssertLessThan(b.maxX, advance.width + 10, "\(font.name) \(ch) hangs past its advance")
                XCTAssertGreaterThan(b.minY, -35, "\(font.name) \(ch) drops too far below the baseline")
                XCTAssertLessThan(b.maxY, 105, "\(font.name) \(ch) rises too far above the baseline")
            }
        }
    }

    func testRealOutlinesAreFilledNotHollow() throws {
        // The glyphs are built from overlapping clockwise pieces; a rasterizer must fill the overlaps
        // (a winding bug would cancel them out and punch holes in the middle of strokes).
        for font in originals {
            var spec = FontSpec(family: font.id, size: 100)
            spec.weight = 0
            let raster = try XCTUnwrap(TextRasterizer.rasterize("H", font: spec, scale: 1), font.name)
            let ink = raster.pixels.enumerated().filter { $0.offset % 4 == 3 && $0.element > 200 }.count
            // The thinnest fonts (Thorn, Monoline Round) still put several hundred solid pixels in an H at
            // 100 pt; a glyph whose overlaps had cancelled out would be riddled with holes and far below.
            XCTAssertGreaterThan(ink, 450, "\(font.name) H has almost no solid pixels: \(ink)")
        }
    }

    func testOriginalsRenderDifferently() throws {
        var seen: [[UInt8]: String] = [:]
        for font in originals {
            let raster = try XCTUnwrap(TextRasterizer.rasterize("Hamburgefonts", font: FontSpec(family: font.id, size: 40), scale: 1), font.name)
            if let other = seen[raster.pixels] { XCTFail("\(font.name) renders exactly like \(other)") }
            seen[raster.pixels] = font.name
        }
    }

    func testRenderedFontsAreNotTheSystemFallback() throws {
        let fallback = try XCTUnwrap(TextRasterizer.rasterize("Hamburgefonts", font: FontSpec(family: "System", size: 40, weight: 0), scale: 1)).pixels
        for font in originals {
            let raster = try XCTUnwrap(TextRasterizer.rasterize("Hamburgefonts", font: FontSpec(family: font.id, size: 40), scale: 1))
            XCTAssertNotEqual(raster.pixels, fallback, "\(font.name) rendered as the system font")
        }
    }

    // MARK: - Registration

    func testFontResolverFindsEachOriginalByItsOwnName() {
        for font in originals {
            let resolved = CTFontCopyPostScriptName(FontResolver.ctFont(FontSpec(family: font.id, size: 40))) as String
            XCTAssertEqual(resolved, font.id, "\(font.name) fell back to \(resolved)")
            XCTAssertTrue(FontCatalog.isInstalled(font.id))
        }
    }

    func testRegisterBundledFontsWithAnOverrideFolder() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("lyra-fonts-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp); FontCatalog.bundledDirectoryOverride = nil }
        for font in originals { try FileManager.default.copyItem(at: url(font), to: temp.appendingPathComponent(font.id + ".ttf")) }

        FontCatalog.bundledDirectoryOverride = temp
        XCTAssertEqual(FontCatalog.bundledFontDirectories(), [temp], "the override replaces every other location")
        XCTAssertEqual(FontCatalog.registerBundledFonts(), originals.count, "every copied file is newly registered")
        XCTAssertEqual(FontCatalog.registerBundledFonts(), 0, "calling again registers nothing twice")
        for font in originals {
            XCTAssertEqual(CTFontCopyPostScriptName(FontResolver.ctFont(FontSpec(family: font.id, size: 40))) as String, font.id)
        }
    }

    func testRegisterBundledFontsNeverThrowsOnAnEmptyOrMissingFolder() {
        defer { FontCatalog.bundledDirectoryOverride = nil }
        FontCatalog.bundledDirectoryOverride = FileManager.default.temporaryDirectory.appendingPathComponent("does-not-exist-\(UUID().uuidString)")
        XCTAssertEqual(FontCatalog.registerBundledFonts(), 0)
    }

    func testRegisterUserFontsAlsoRegistersTheBundledOnes() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("lyra-fonts-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp); FontCatalog.bundledDirectoryOverride = nil; FontCatalog.directoryOverride = nil }
        try FileManager.default.copyItem(at: url(originals[0]), to: temp.appendingPathComponent("LyraForge-Regular.ttf"))
        FontCatalog.bundledDirectoryOverride = temp
        FontCatalog.directoryOverride = FileManager.default.temporaryDirectory.appendingPathComponent("no-user-fonts-\(UUID().uuidString)")
        // The app only calls registerUserFonts() at launch: that single call must cover the bundled fonts.
        FontCatalog.registerUserFonts()
        XCTAssertEqual(FontCatalog.registerBundledFonts(), 0, "registerUserFonts already registered them")
    }

    // MARK: - Where the fonts are looked for

    func testDiscoveryOrderAndFiltering() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lyra-discovery-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func makeFonts(at dir: URL, named name: String = "LyraForge-Regular.ttf") throws {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data([0]).write(to: dir.appendingPathComponent(name))
        }
        // A packaged app, an environment folder, and a development checkout the executable sits inside.
        let resources = root.appendingPathComponent("Lyra.app/Contents/Resources", isDirectory: true)
        try makeFonts(at: resources.appendingPathComponent("Fonts"))
        let envDir = root.appendingPathComponent("elsewhere", isDirectory: true)
        try makeFonts(at: envDir)
        let project = root.appendingPathComponent("project", isDirectory: true)
        try makeFonts(at: project.appendingPathComponent("Fonts"))
        let executable = project.appendingPathComponent("LyraApp/.build/debug", isDirectory: true)
        try FileManager.default.createDirectory(at: executable, withIntermediateDirectories: true)

        FontCatalog.bundledDirectoryOverride = nil
        let found = FontCatalog.bundledFontDirectories(resourceURL: resources, environment: ["LYRA_FONTS_DIR": envDir.path],
                                                       executableURL: executable.appendingPathComponent("lyra-app"),
                                                       workingDirectory: root.path)
        XCTAssertEqual(found.map { $0.standardizedFileURL.path },
                       [resources.appendingPathComponent("Fonts"), envDir, project.appendingPathComponent("Fonts")].map { $0.standardizedFileURL.path },
                       "bundle first, then the environment, then the checkout found by walking up")

        // Folders without Lyra fonts are skipped, and a folder is never listed twice.
        let empty = root.appendingPathComponent("empty", isDirectory: true)
        try FileManager.default.createDirectory(at: empty.appendingPathComponent("Fonts"), withIntermediateDirectories: true)
        try Data([0]).write(to: empty.appendingPathComponent("Fonts/Other.ttf"))
        let none = FontCatalog.bundledFontDirectories(resourceURL: empty, environment: ["LYRA_FONTS_DIR": empty.appendingPathComponent("Fonts").path],
                                                      executableURL: empty.appendingPathComponent("exe"), workingDirectory: empty.path)
        XCTAssertTrue(none.isEmpty)
        let dup = FontCatalog.bundledFontDirectories(resourceURL: resources, environment: ["LYRA_FONTS_DIR": resources.appendingPathComponent("Fonts").path],
                                                     executableURL: nil, workingDirectory: "/nonexistent")
        XCTAssertEqual(dup.count, 1)
    }
}
