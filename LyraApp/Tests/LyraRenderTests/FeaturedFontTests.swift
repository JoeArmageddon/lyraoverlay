import XCTest
import CoreText
import LyraCore
@testable import LyraRender

final class FeaturedFontTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Lyra's own fonts are registered at launch in the app; tests do it themselves.
        FontCatalog.registerBundledFonts()
    }

    private func postScriptName(_ family: String) -> String {
        CTFontCopyPostScriptName(FontResolver.ctFont(FontSpec(family: family, size: 40))) as String
    }

    /// True when `family` resolves to its own face rather than silently falling back to the system font.
    private func resolvesToItself(_ family: String) -> Bool {
        if family == "System" { return true }
        return postScriptName(family) == family
    }

    func testHasAtLeastTwentySixFonts() {
        XCTAssertGreaterThanOrEqual(FontCatalog.featured.count, 26)
    }

    func testIDsAndNamesAreUnique() {
        XCTAssertEqual(Set(FontCatalog.featured.map(\.id)).count, FontCatalog.featured.count)
        XCTAssertEqual(Set(FontCatalog.featured.map(\.name)).count, FontCatalog.featured.count)
    }

    func testEveryFeaturedFontIsInstalledAndResolvesToARealFace() {
        for font in FontCatalog.featured {
            XCTAssertTrue(FontCatalog.isInstalled(font.id), "\(font.name) (\(font.id)) is not installed")
            XCTAssertTrue(resolvesToItself(font.id), "\(font.name) resolved to \(postScriptName(font.id)), not \(font.id)")
        }
    }

    func testTheFeaturedListIsCachedAndStable() {
        XCTAssertEqual(FontCatalog.featured, FontCatalog.featured)
        XCTAssertEqual(FontCatalog.handDrawn, FontCatalog.handDrawn)
        XCTAssertEqual(FontCatalog.featured.filter { $0.category == .handDrawn }, FontCatalog.handDrawn)
        XCTAssertEqual(FontCatalog.featured.prefix(FontCatalog.originals.count).map(\.id), FontCatalog.originalIDs)
    }

    func testReadingTheCatalogIsCheapAndThreadSafe() {
        _ = FontCatalog.featured
        let start = Date()
        DispatchQueue.concurrentPerform(iterations: 400) { _ in
            _ = FontCatalog.featured.count + FontCatalog.handDrawn.count
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.0, "400 reads should not rescan the font folders")
    }

    func testAvailableFeaturedIsEverythingOnThisMac() {
        XCTAssertEqual(FontCatalog.availableFeatured(), FontCatalog.featured)
    }

    func testOriginalsComeFirstAndGimmickFontsComeLast() {
        let groups = FontCatalog.featuredByCategory()
        XCTAssertEqual(groups.first?.0, .originals)
        XCTAssertEqual(groups.last?.0, .novelty)
        XCTAssertEqual(FontCategory.originals.title, "Lyra Originals")
        XCTAssertEqual(FontCategory.novelty.title, "More System Fonts")
        XCTAssertEqual(groups.first?.1.map(\.id), FontCatalog.originalIDs, "every Lyra Original is found and installed")
    }

    func testGimmickFontsAreGroupedAsNoveltyAndNoThemeUsesThem() {
        let gimmicks = ["Papyrus", "Herculanum", "Phosphate-Solid", "Luminari-Regular", "PartyLetPlain", "Trattatello", "Chalkduster",
                        "ComicSansMS-Bold", "MarkerFelt-Wide", "SignPainter-HouseScript", "Zapfino", "BrushScriptMT", "Silom",
                        "BradleyHandITCTT-Bold", "Noteworthy-Bold", "Apple-Chancery", "SnellRoundhand-Black"]
        for id in gimmicks {
            XCTAssertEqual(FontCatalog.featured.first { $0.id == id }?.category, .novelty, "\(id) should be under More System Fonts")
        }
        let novelty = Set(FontCatalog.featured.filter { $0.category == .novelty }.map(\.id))
        for theme in BuiltInThemes.all {
            XCTAssertFalse(novelty.contains(theme.overlay.font.family), "\(theme.name) uses a novelty font")
        }
    }

    func testTheCuratedSystemFontsAreTasteful() {
        // The sans, serif, display, mono, rounded and condensed groups hold no gimmick faces.
        let ids = Set(FontCatalog.featured.filter { ![.novelty, .originals, .handDrawn].contains($0.category) }.map(\.id))
        for bad in ["Papyrus", "Chalkduster", "ComicSansMS-Bold", "MarkerFelt-Wide", "Zapfino", "PartyLetPlain"] {
            XCTAssertFalse(ids.contains(bad), "\(bad) should not be in a main group")
        }
        XCTAssertGreaterThanOrEqual(ids.count, 26, "plenty of good system fonts remain")
    }

    func testDisplayNames() {
        XCTAssertEqual(FontCatalog.displayName(for: "LyraForge-Regular"), "Lyra Forge")
        XCTAssertEqual(FontCatalog.displayName(for: "System"), "SF Pro (System)")
        XCTAssertEqual(FontCatalog.displayName(for: "Some Imported Font"), "Some Imported Font", "unknown families show as stored")
        XCTAssertEqual(FontCatalog.displayName(for: ""), "System")
    }

    func testEveryCategoryIsUsedAndGroupingCoversEverything() {
        XCTAssertEqual(Set(FontCatalog.featured.map(\.category)), Set(FontCategory.allCases))
        let groups = FontCatalog.featuredByCategory()
        XCTAssertEqual(groups.map(\.0), FontCategory.allCases, "stable order, no empty categories")
        XCTAssertEqual(groups.flatMap(\.1).count, FontCatalog.featured.count)
        for (category, fonts) in groups { XCTAssertTrue(fonts.allSatisfy { $0.category == category }) }
        XCTAssertTrue(FontCategory.allCases.allSatisfy { !$0.title.isEmpty })
    }

    func testFontsRenderDifferently() throws {
        let fonts = FontCatalog.featured
        func pixels(_ id: String) throws -> [UInt8] {
            try XCTUnwrap(TextRasterizer.rasterize("Hamburgefonts", font: FontSpec(family: id, size: 40), scale: 1), id).pixels
        }
        // Compare neighbors and a spread of distant pairs, so a silent fallback to the same face shows up.
        var pairs: [(Int, Int)] = (0..<fonts.count - 1).map { ($0, $0 + 1) }
        pairs += (0..<fonts.count).map { ($0, ($0 + 7) % fonts.count) }
        var checked = 0
        for (i, j) in pairs where i != j {
            XCTAssertNotEqual(try pixels(fonts[i].id), try pixels(fonts[j].id), "\(fonts[i].name) renders the same as \(fonts[j].name)")
            checked += 1
        }
        XCTAssertGreaterThanOrEqual(checked, 20)
    }

    // MARK: - Themes use real fonts

    func testEveryThemeFontIsInstalledAndResolvesToARealFace() {
        for theme in BuiltInThemes.all {
            let family = theme.overlay.font.family
            XCTAssertTrue(FontCatalog.isInstalled(family), "\(theme.name) uses \(family), which isn't installed")
            XCTAssertTrue(resolvesToItself(family), "\(theme.name): \(family) resolved to \(postScriptName(family))")
        }
    }

    func testEveryThemeFontIsFeatured() {
        let featured = Set(FontCatalog.featured.map(\.id))
        for theme in BuiltInThemes.all {
            XCTAssertTrue(featured.contains(theme.overlay.font.family), "\(theme.name) uses a font that isn't in the featured list")
        }
    }

    func testThemesRenderWithDistinctGlyphs() throws {
        // The themes' fonts must look different from each other, not just have different names.
        var seen: [[UInt8]: String] = [:]
        for theme in BuiltInThemes.all {
            var font = theme.overlay.font
            font.size = 40
            let raster = try XCTUnwrap(TextRasterizer.rasterize("Hamburgefonts", font: font, scale: 1), theme.name)
            if let other = seen[raster.pixels] { XCTFail("\(theme.name) looks identical to \(other)") }
            seen[raster.pixels] = theme.name
        }
    }
}
