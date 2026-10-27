import XCTest
import SwiftUI
import AppKit
import LyraCore
@testable import LyraRender

final class FontPickerLogicTests: XCTestCase {
    private let installed = ["Avenir", "Courier", "Helvetica Neue", "Zapfino Regular", "AvenirNext-Heavy"]

    override func setUp() {
        super.setUp()
        FontCatalog.registerBundledFonts()
    }

    /// No custom fonts here: the groups come from the catalog alone.
    private func groups(query: String = "", chip: FontPicker.Chip = .all, current: String = "System") -> [FontPicker.Group] {
        FontPicker.groups(query: query, chip: chip, installed: installed, current: current, userFonts: [])
    }

    func testOriginalsAreListedFirstThenSystemFontsThenEverythingElse() {
        let titles = groups().map(\.title)
        XCTAssertEqual(titles.first, "Lyra Originals")
        XCTAssertEqual(titles.last, FontPicker.installedTitle)
        XCTAssertEqual(titles.dropLast().last, "More System Fonts", "the gimmick fonts come after every real group")
        // The Lyra groups come first, in the catalog's order, and the system groups follow them.
        XCTAssertEqual(Array(titles.prefix(2)), [FontCategory.originals.title, FontCategory.handDrawn.title])
        XCTAssertEqual(titles.firstIndex(of: "Sans Serif"), 2)
        XCTAssertFalse(titles.contains(FontPicker.myFontsTitle), "no custom fonts, no My Fonts group")
    }

    func testOriginalsGroupHoldsEveryOriginal() {
        let originals = groups().first
        XCTAssertEqual(originals?.rows.map(\.id), FontCatalog.originalIDs)
        XCTAssertEqual(originals?.rows.first?.name, "Lyra Forge")
        let drawn = groups().first { $0.title == FontCategory.handDrawn.title }
        XCTAssertEqual(drawn?.rows.map(\.id), FontCatalog.handDrawn.map(\.id), "every hand-drawn font, however many")
    }

    func testChipsFilterToOneGroup() {
        for case .category(let category) in FontPicker.Chip.all_ {
            let g = groups(chip: .category(category))
            XCTAssertEqual(g.map(\.title), [category.title], "\(category) chip shows only its own group")
        }
        XCTAssertEqual(groups(chip: .category(.originals)).first?.rows.count, FontCatalog.originals.count)
        XCTAssertTrue(groups(chip: .myFonts).isEmpty, "My Fonts is empty without imports")
    }

    func testAllChipListsEveryChip() {
        XCTAssertEqual(FontPicker.Chip.all_.count, FontCategory.allCases.count + 2, "All, My Fonts and every category")
        XCTAssertEqual(FontPicker.Chip.all_.first, .all)
        XCTAssertEqual(FontPicker.Chip.all_[1], .myFonts)
        XCTAssertEqual(FontPicker.Chip.myFonts.title, "My Fonts")
        XCTAssertEqual(FontPicker.Chip.all_.map(\.title).first, "All")
        XCTAssertTrue(FontPicker.Chip.all_.map(\.title).contains("More System Fonts"))
    }

    func testSearchMatchesNamesCaseInsensitively() {
        let g = groups(query: "FORGE")
        XCTAssertEqual(g.map(\.title), ["Lyra Originals", "Lyra Hand-Drawn"], "Forge and Forge Drawn")
        XCTAssertEqual(g.first?.rows.map(\.id), ["LyraForge-Regular"])
        XCTAssertEqual(g.last?.rows.map(\.id), ["LyraForgeDrawn-Regular"])
        XCTAssertEqual(groups(query: "  forge  ").count, 2, "surrounding spaces are ignored")
        XCTAssertTrue(groups(query: "zzzz no such font").isEmpty)
    }

    func testSearchReachesInstalledFontsToo() {
        let g = groups(query: "courier")
        XCTAssertTrue(g.contains { $0.title == FontPicker.installedTitle && $0.rows.map(\.id).contains("Courier") })
    }

    func testInstalledSectionSkipsFeaturedFontsAndOnlyShowsOnAll() {
        let installedGroup = groups().first { $0.title == FontPicker.installedTitle }
        XCTAssertNotNil(installedGroup)
        XCTAssertFalse(installedGroup!.rows.map(\.id).contains("AvenirNext-Heavy"), "already listed as a featured font")
        XCTAssertTrue(groups(chip: .category(.serif)).allSatisfy { $0.title != FontPicker.installedTitle })
    }

    func testAnInstalledCurrentFontStillAppearsSoTheSelectionIsNeverBlank() {
        // Futura Medium is installed, not featured and not in this test's installed list.
        let g = groups(current: "Futura-Medium")
        XCTAssertEqual(g.first { $0.title == FontPicker.installedTitle }?.rows.first?.id, "Futura-Medium")
        // A featured current font is not duplicated into the installed list.
        let featured = groups(current: "LyraForge-Regular").first { $0.title == FontPicker.installedTitle }
        XCTAssertFalse(featured!.rows.map(\.id).contains("LyraForge-Regular"))
    }

    func testAMissingCurrentFontGetsANoteInsteadOfABlankRow() {
        XCTAssertNil(FontPicker.missingFontNote(current: "System"))
        XCTAssertNil(FontPicker.missingFontNote(current: ""))
        XCTAssertNil(FontPicker.missingFontNote(current: "LyraForge-Regular"))
        let note = FontPicker.missingFontNote(current: "Some Removed Font")
        XCTAssertTrue(note?.contains("Some Removed Font") == true && note?.contains("system font") == true, note ?? "nil")
        let rows = groups(current: "Some Removed Font").flatMap(\.rows)
        XCTAssertFalse(rows.contains { $0.id == "Some Removed Font" }, "no phantom row for a font that isn't there")
    }

    func testNoFontAppearsTwice() {
        let ids = groups().flatMap(\.rows).map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testSamplePhrasesAreInventedNeutralAndRotate() {
        XCTAssertGreaterThanOrEqual(FontPreview.samples.count, 6)
        XCTAssertEqual(Set(FontPreview.samples).count, FontPreview.samples.count)
        XCTAssertNotEqual(FontPreview.sample(0), FontPreview.sample(1))
        XCTAssertEqual(FontPreview.sample(0), FontPreview.sample(FontPreview.samples.count), "wraps around")
        XCTAssertFalse(FontPreview.sample(-3).isEmpty, "negative indexes are safe")
    }
}

final class FontPickerRenderTests: XCTestCase {
    private var userFolder: URL!

    override func setUp() {
        super.setUp()
        // Never the real Application Support folder.
        userFolder = FileManager.default.temporaryDirectory.appendingPathComponent("lyra-picker-fonts-\(UUID().uuidString)", isDirectory: true)
        FontCatalog.directoryOverride = userFolder
    }

    override func tearDown() {
        FontCatalog.directoryOverride = nil
        try? FileManager.default.removeItem(at: userFolder)
        super.tearDown()
    }

    private func tempThemes() -> ThemeStore {
        ThemeStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("lyra-picker-\(UUID().uuidString)"))
    }

    /// Renders a view on a dark panel the way the popover shows it.
    private func render<V: View>(_ view: V) throws -> NSBitmapImageRep {
        let host = NSHostingView(rootView: view.background(Color(white: 0.16)).environment(\.colorScheme, .dark))
        let size = host.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.alphaValue = 0
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        window.effectiveAppearance.performAsCurrentDrawingAppearance { host.cacheDisplay(in: host.bounds, to: rep) }
        window.orderOut(nil)
        return rep
    }

    private func pixels(_ rep: NSBitmapImageRep) -> [UInt8] {
        guard let data = rep.bitmapData else { return [] }
        return Array(UnsafeBufferPointer(start: data, count: rep.bytesPerRow * rep.pixelsHigh))
    }

    private func distinctColors(_ rep: NSBitmapImageRep, step: Int = 5) -> Int {
        var seen = Set<UInt32>()
        for y in stride(from: 0, to: rep.pixelsHigh, by: step) {
            for x in stride(from: 0, to: rep.pixelsWide, by: step) {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                seen.insert(UInt32(c.redComponent * 15) << 8 | UInt32(c.greenComponent * 15) << 4 | UInt32(c.blueComponent * 15))
            }
        }
        return seen.count
    }

    func testThePickerRendersAndIsNotBlank() throws {
        FontCatalog.registerBundledFonts()
        let model = SettingsModel(settings: AppSettings(), themeStore: tempThemes())
        let rep = try render(FontPicker(model: model))
        XCTAssertEqual(rep.pixelsWide, 480 * Int(rep.pixelsWide / 480), "480 points wide at the display's scale")
        XCTAssertGreaterThan(rep.pixelsHigh, 500)
        XCTAssertGreaterThan(distinctColors(rep), 12, "text, chips and rows should give more than a flat panel")

        if let dir = ProcessInfo.processInfo.environment["LYRA_SNAPSHOT_DIR"], let png = rep.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("font-picker.png"))
        }
    }

    func testTwoDifferentFontsDrawDifferentSampleRows() throws {
        FontCatalog.registerBundledFonts()
        let a = try render(FontRow(id: "LyraForge-Regular", name: "Same name", sample: "Midnight in the city lights", selected: false))
        let b = try render(FontRow(id: "LyraPixel-Regular", name: "Same name", sample: "Midnight in the city lights", selected: false))
        XCTAssertNotEqual(pixels(a), pixels(b), "the sample line must be drawn in the row's own font")
        XCTAssertGreaterThan(distinctColors(a, step: 2), 4)
    }

    func testTheSelectedRowIsMarked() throws {
        let plain = try render(FontRow(id: "LyraNeonTube-Regular", name: "Lyra Neon Tube", sample: "Hold on to the feeling", selected: false))
        let chosen = try render(FontRow(id: "LyraNeonTube-Regular", name: "Lyra Neon Tube", sample: "Hold on to the feeling", selected: true))
        XCTAssertNotEqual(pixels(plain), pixels(chosen), "a checkmark and highlight show the current font")
    }

    func testThemeCardsPreviewEachThemeInItsOwnFont() throws {
        FontCatalog.registerBundledFonts()
        func card(_ id: String) throws -> NSBitmapImageRep {
            let theme = try XCTUnwrap(BuiltInThemes.theme(id: id))
            return try render(ThemeCard(theme: theme, active: false).frame(width: 180))
        }
        // Same size and layout, different typefaces: the cards must not look alike.
        XCTAssertNotEqual(pixels(try card("builtin.forge")), pixels(try card("builtin.arcade")))
        XCTAssertNotEqual(pixels(try card("builtin.classic")), pixels(try card("builtin.noir")))

        // Selecting a theme outlines its card.
        let theme = try XCTUnwrap(BuiltInThemes.theme(id: "builtin.thorn"))
        let plain = try render(ThemeCard(theme: theme, active: false).frame(width: 180))
        let active = try render(ThemeCard(theme: theme, active: true).frame(width: 180))
        XCTAssertNotEqual(pixels(plain), pixels(active))

        // A contact sheet of the first dozen themes, to look at.
        let sheet = try render(
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(180), spacing: 10), count: 3), spacing: 10) {
                ForEach(Array(BuiltInThemes.all.prefix(12))) { ThemeCard(theme: $0, active: $0.id == "builtin.forge") }
            }.padding(12).frame(width: 620)
        )
        XCTAssertGreaterThan(distinctColors(sheet), 12)
        if let dir = ProcessInfo.processInfo.environment["LYRA_SNAPSHOT_DIR"], let png = sheet.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("theme-cards.png"))
        }
    }

    func testPreviewFontsResolveThroughTheSameResolverAsTheOverlay() {
        FontCatalog.registerBundledFonts()
        for id in ["LyraForge-Regular", "LyraPixel-Regular", "AvenirNext-Heavy", "System"] {
            let ct = FontResolver.ctFont(FontSpec(family: id, size: 24))
            XCTAssertEqual(CTFontGetSize(ct), 24, accuracy: 0.01, id)
        }
    }

    private func snapshot(_ rep: NSBitmapImageRep, _ name: String) throws {
        if let dir = ProcessInfo.processInfo.environment["LYRA_SNAPSHOT_DIR"], let png = rep.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
        }
    }

    func testTheEmptyMyFontsStateInvitesYouToAddFonts() throws {
        FontCatalog.registerBundledFonts()
        let model = SettingsModel(settings: AppSettings(), themeStore: tempThemes())
        let empty = try render(FontPicker(model: model, initialChip: .myFonts))
        let all = try render(FontPicker(model: model))
        XCTAssertNotEqual(pixels(empty), pixels(all))
        XCTAssertEqual(FontPicker.emptyStateText, "Drop font files here or click Add Custom Font")
        XCTAssertGreaterThan(distinctColors(empty), 6)
        try snapshot(empty, "font-picker-empty.png")
    }

    func testMyFontsShowImportedFontsAndTheMissingNote() throws {
        FontCatalog.registerBundledFonts()
        let a = try TestFont.makeUnique(in: userFolder.deletingLastPathComponent().appendingPathComponent("src-\(UUID().uuidString)"))
        let b = try TestFont.makeUnique(in: a.url.deletingLastPathComponent())
        defer { try? FileManager.default.removeItem(at: a.url.deletingLastPathComponent()) }
        XCTAssertTrue(FontCatalog.importFonts(urls: [a.url, b.url]).allSatisfy(\.succeeded))

        var settings = AppSettings()
        settings.overlay.font.family = a.postScript
        let model = SettingsModel(settings: settings, themeStore: tempThemes())
        let mine = try render(FontPicker(model: model, initialChip: .myFonts))
        let empty = try render(FontPicker(model: model, initialChip: .category(.originals)))
        XCTAssertNotEqual(pixels(mine), pixels(empty))
        try snapshot(mine, "font-picker-my-fonts.png")

        // Remove the selected font: the picker shows a note, still renders, and the setting is untouched.
        try FontCatalog.removeUserFont(at: userFolder.appendingPathComponent(a.url.lastPathComponent))
        var gone = AppSettings()
        gone.overlay.font.family = "Removed Custom Font"
        let missing = try render(FontPicker(model: SettingsModel(settings: gone, themeStore: tempThemes())))
        XCTAssertNotEqual(pixels(missing), pixels(try render(FontPicker(model: SettingsModel(settings: AppSettings(), themeStore: tempThemes())))),
                          "the note changes the picture")
        XCTAssertEqual(model.settings.overlay.font.family, a.postScript, "removing a font never rewrites settings")
        try snapshot(missing, "font-picker-missing-note.png")
    }
}
