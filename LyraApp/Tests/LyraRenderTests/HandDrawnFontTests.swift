import XCTest
import CoreText
import LyraCore
@testable import LyraRender

/// The hand-drawn Lyra fonts (copied from `Fonts/drawn` into `Fonts/` by `Scripts/install-fonts.sh`; any number), checked the way
/// `OriginalFontTests` checks the generated eight: through CoreText and Lyra's own resolver.
final class HandDrawnFontTests: XCTestCase {
    private let fontsDir: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fonts", isDirectory: true)

    private var drawn: [FeaturedFont] { FontCatalog.handDrawn }
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

    // MARK: - Catalog

    /// Every `Lyra*.ttf` in Fonts/ that is not one of the generated originals.
    private func drawnFileIDs() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: fontsDir.path)
            .filter { $0.hasPrefix("Lyra") && $0.hasSuffix(".ttf") && !$0.contains(".tmp") }
            .map { ($0 as NSString).deletingPathExtension }
            .filter { !FontCatalog.originalIDs.contains($0) }
    }

    func testTheCatalogIsDerivedFromTheFilesInFonts() throws {
        let expected = try drawnFileIDs()
        XCTAssertGreaterThanOrEqual(expected.count, 12, "the hand-drawn set only grows")
        XCTAssertEqual(Set(drawn.map(\.id)), Set(expected), "a Lyra font in Fonts/ is missing from the catalog, or the reverse")
        XCTAssertEqual(drawn.count, expected.count)
        XCTAssertTrue(drawn.allSatisfy { $0.category == .handDrawn })
        XCTAssertEqual(drawn.map(\.name), drawn.map(\.name).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }, "sorted by display name")
    }

    func testHandDrawnFontsSitRightAfterTheOriginalsAndAreAllInstalled() throws {
        XCTAssertEqual(FontCategory.handDrawn.title, "Lyra Hand-Drawn")
        let groups = FontCatalog.featuredByCategory()
        XCTAssertEqual(groups.prefix(2).map(\.0), [.originals, .handDrawn])
        XCTAssertEqual(groups[1].1.map(\.id), drawn.map(\.id), "every hand-drawn font is found and installed")
        XCTAssertEqual(FontCatalog.displayName(for: "LyraBrush-Regular"), "Lyra Brush")
        XCTAssertEqual(FontCatalog.displayName(for: "LyraForgeDrawn-Regular"), "Lyra Forge Drawn")
        XCTAssertEqual(FontCatalog.displayName(for: "LyraScript-Regular"), "Lyra Script", "new fonts need no code edit")
    }

    func testANewFontFileAppearsWithoutACodeEdit() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("lyra-newfont-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temp); FontCatalog.bundledDirectoryOverride = nil }
        // Renamed copies, so registering them never shadows a real Lyra font for the other tests.
        let b = try TestFont.makeUnique(in: temp, fileName: "Lyrazzb-Regular.ttf", lyraTag: "zzb")
        let a = try TestFont.makeUnique(in: temp, fileName: "Lyrazza-Regular.ttf", lyraTag: "zza")
        _ = try TestFont.makeUnique(in: temp, fileName: "Lyrazzp-Regular.tmp.ttf", lyraTag: "zzp")   // half-written: ignored
        _ = try TestFont.makeUnique(in: temp, fileName: "Other-Regular.ttf", lyraTag: "zzo")         // not named Lyra*: ignored
        FontCatalog.bundledDirectoryOverride = temp
        XCTAssertEqual(FontCatalog.handDrawn.map(\.id), [a.postScript, b.postScript], "sorted by display name; partial and non-Lyra files skipped")
        XCTAssertEqual(FontCatalog.handDrawn.map(\.name), ["Lyra zza", "Lyra zzb"])

        // A font that arrives later shows up once registerBundledFonts sees it.
        let c = try TestFont.makeUnique(in: temp, fileName: "Lyrazzc-Regular.ttf", lyraTag: "zzc")
        XCTAssertEqual(FontCatalog.handDrawn.count, 2, "the cache holds until something registers new files")
        XCTAssertEqual(FontCatalog.registerBundledFonts(), 4, "a, b, c and Other are registered (every font file is); the .tmp file never is")
        XCTAssertEqual(FontCatalog.handDrawn.map(\.id), [a.postScript, b.postScript, c.postScript])
        XCTAssertTrue(FontCatalog.featured.contains { $0.id == c.postScript && $0.category == .handDrawn })
        XCTAssertTrue(FontCatalog.isInstalled(c.postScript))
    }

    func testIDsAreUniqueAcrossEveryLyraFont() {
        let ids = (FontCatalog.originals + drawn).map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "a drawn font reuses a PostScript name")
        let names = (FontCatalog.originals + drawn).map(\.name)
        XCTAssertEqual(Set(names).count, names.count, "two fonts show the same name in the picker")
    }

    // MARK: - Files and licensing

    func testFilesArePresentAndNotEmpty() throws {
        for font in drawn {
            let attributes = try FileManager.default.attributesOfItem(atPath: url(font).path)
            XCTAssertGreaterThan(attributes[.size] as? Int ?? 0, 5_000, "\(font.id).ttf is missing or empty in Fonts/")
        }
    }

    func testEachFontStatesItsOwnCopyrightAndTheOpenFontLicense() throws {
        for font in drawn {
            let ct = CTFontCreateWithFontDescriptor(try descriptor(font), 20, nil)
            let copyright = (CTFontCopyName(ct, kCTFontCopyrightNameKey) as String?) ?? ""
            XCTAssertTrue(copyright.contains("2026") && copyright.contains("Lyra"), "\(font.name) copyright: \(copyright)")
            let license = (CTFontCopyName(ct, kCTFontLicenseNameKey) as String?) ?? ""
            XCTAssertTrue(license.contains("SIL Open Font License"), "\(font.name) license: \(license)")
        }
    }

    func testEveryFontLoadsAndMatchesItsCatalogEntry() throws {
        for font in drawn {
            let d = try descriptor(font)
            XCTAssertEqual(CTFontDescriptorCopyAttribute(d, kCTFontNameAttribute) as? String, font.id)
            XCTAssertEqual(CTFontDescriptorCopyAttribute(d, kCTFontFamilyNameAttribute) as? String,
                           font.name.replacingOccurrences(of: " Drawn", with: " Drawn"), "\(font.id)")
        }
    }

    // MARK: - Coverage

    private let required: [Character] = {
        var c: [Character] = []
        for u in UnicodeScalar("A").value...UnicodeScalar("Z").value { c.append(Character(UnicodeScalar(u)!)) }
        for u in UnicodeScalar("a").value...UnicodeScalar("z").value { c.append(Character(UnicodeScalar(u)!)) }
        c += Array("0123456789.,!?'\"-:;&()/#@%+=$*_~ ")
        c += Array("áàâäãåéèêëíìîïóòôöõúùûüñçýÿÁÀÂÄÃÅÉÈÊËÍÌÎÏÓÒÔÖÕÚÙÛÜÑÇÝ")
        return c
    }()

    func testEveryFontCoversEveryRequiredCharacter() throws {
        for font in drawn {
            let ct = CTFontCreateWithFontDescriptor(try descriptor(font), 100, nil)
            for ch in required {
                let units = Array(String(ch).utf16)
                var glyphs = [CGGlyph](repeating: 0, count: units.count)
                XCTAssertTrue(CTFontGetGlyphsForCharacters(ct, units, &glyphs, units.count), "\(font.name) has no glyph for \(ch)")
            }
        }
    }

    func testLettersAndDigitsDrawSomethingWithAPositiveAdvance() throws {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
        for font in drawn {
            let ct = CTFontCreateWithFontDescriptor(try descriptor(font), 100, nil)
            for ch in chars {
                var unit = UniChar(ch.unicodeScalars.first!.value)
                var glyph = CGGlyph()
                XCTAssertTrue(CTFontGetGlyphsForCharacters(ct, &unit, &glyph, 1))
                let path = try XCTUnwrap(CTFontCreatePathForGlyph(ct, glyph, nil), "\(font.name) \(ch) has no outline")
                XCTAssertFalse(path.boundingBoxOfPath.isEmpty, "\(font.name) \(ch) draws nothing")
                var advance = CGSize.zero
                CTFontGetAdvancesForGlyphs(ct, .horizontal, &glyph, &advance, 1)
                XCTAssertGreaterThan(advance.width, 5, "\(font.name) \(ch) has no width")
            }
        }
    }

    func testMetricsAreSane() throws {
        for font in drawn {
            let ct = CTFontCreateWithFontDescriptor(try descriptor(font), 100, nil)
            XCTAssertEqual(CTFontGetUnitsPerEm(ct), 1000, font.name)
            XCTAssertEqual(CTFontGetAscent(ct), 80, accuracy: 1, font.name)
            XCTAssertEqual(CTFontGetDescent(ct), 20, accuracy: 1, font.name)
            XCTAssertEqual(CTFontGetLeading(ct), 0, accuracy: 1, font.name)
            XCTAssertTrue(CTFontGetXHeight(ct) > 40 && CTFontGetXHeight(ct) <= 70.5, "\(font.name) x-height \(CTFontGetXHeight(ct))")
        }
    }

    /// Letters may overshoot the ascender a little (a brush or tag swash), but a glyph that towers over
    /// or sinks far below the line would collide with neighbouring lines.
    func testNoGlyphWildlyExceedsTheLine() throws {
        for font in drawn {
            let ct = CTFontCreateWithFontDescriptor(try descriptor(font), 100, nil)
            for ch in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789" {
                var unit = UniChar(ch.unicodeScalars.first!.value)
                var glyph = CGGlyph()
                CTFontGetGlyphsForCharacters(ct, &unit, &glyph, 1)
                let box = CTFontCreatePathForGlyph(ct, glyph, nil)?.boundingBoxOfPath ?? .zero
                XCTAssertLessThan(box.maxY, 100, "\(font.name) \(ch) rises \(box.maxY) pt on a 100 pt font")
                XCTAssertGreaterThan(box.minY, -40, "\(font.name) \(ch) sinks \(box.minY) pt")
            }
        }
    }

    // MARK: - Resolver and rendering

    func testTheResolverFindsEachFontByItsPostScriptName() throws {
        for font in drawn {
            let ct = FontResolver.ctFont(FontSpec(family: font.id, size: 40))
            XCTAssertEqual(CTFontCopyPostScriptName(ct) as String, font.id, "\(font.name) fell back to another font")
            XCTAssertTrue(FontCatalog.isInstalled(font.id))
        }
    }

    func testEveryFontLooksDifferentFromEveryOther() throws {
        func pixels(_ font: FeaturedFont) throws -> [UInt8] {
            try XCTUnwrap(TextRasterizer.rasterize("Hamburgefonstiv", font: FontSpec(family: font.id, size: 60), scale: 1), font.name).pixels
        }
        var rendered: [(String, [UInt8])] = []
        for font in FontCatalog.originals + drawn { rendered.append((font.name, try pixels(font))) }
        for i in 0..<rendered.count {
            for j in (i + 1)..<rendered.count {
                XCTAssertNotEqual(rendered[i].1, rendered[j].1, "\(rendered[i].0) and \(rendered[j].0) render identically")
            }
        }
    }

    func testLowercaseIsRealNotJustSmallCaps() throws {
        // The drawn fonts have their own lowercase: 'a' and 'A' differ in at least most of them.
        var distinct = 0
        for font in drawn {
            func pixels(_ s: String) -> [UInt8]? { TextRasterizer.rasterize(s, font: FontSpec(family: font.id, size: 60), scale: 1)?.pixels }
            if let a = pixels("agbdeq"), let b = pixels("AGBDEQ"), a != b { distinct += 1 }
        }
        XCTAssertGreaterThanOrEqual(distinct, drawn.count * 2 / 3, "most hand-drawn fonts should have a true lowercase")
    }
}
