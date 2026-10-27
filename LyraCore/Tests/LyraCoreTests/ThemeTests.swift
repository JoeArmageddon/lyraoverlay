import XCTest
@testable import LyraCore

private func tempDir() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("lyra-themes-\(UUID().uuidString)", isDirectory: true)
}

final class BuiltInThemeTests: XCTestCase {
    func testIDsAreUniqueAndStable() {
        let ids = BuiltInThemes.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertTrue(ids.allSatisfy { $0.hasPrefix("builtin.") })
        XCTAssertEqual(BuiltInThemes.all.first?.id, BuiltInThemes.classicID, "Classic is the default and comes first")
    }

    func testNamesAreUniqueAndNonEmpty() {
        let names = BuiltInThemes.all.map(\.name)
        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertTrue(names.allSatisfy { !$0.isEmpty })
    }

    func testPresetsAreDistinct() {
        let looks = BuiltInThemes.all.map { "\($0.styleID)|\($0.overlay.font.family)|\($0.overlay.glow)|\($0.lights.enabled)" }
        XCTAssertEqual(Set(looks).count, looks.count, "no two presets should look the same")
    }

    func testEveryPresetSurvivesAJSONRoundTrip() throws {
        for theme in BuiltInThemes.all {
            let data = try ThemeStore.encode(theme)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
            try data.write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }
            XCTAssertEqual(try ThemeStore.read(url), theme, theme.name)
        }
    }

    func testLookupByID() {
        XCTAssertEqual(BuiltInThemes.theme(id: "builtin.neon")?.name, "Neon")
        XCTAssertNil(BuiltInThemes.theme(id: "builtin.nope"))
    }
}

final class ThemeTests: XCTestCase {
    func testApplyingKeepsTheUsersSyncOffset() {
        var current = OverlayConfig()
        current.latencyOffset = 0.4
        let applied = BuiltInThemes.neon.overlay(preservingSyncFrom: current)
        XCTAssertEqual(applied.latencyOffset, 0.4)
        XCTAssertEqual(applied.glow, BuiltInThemes.neon.overlay.glow)
        XCTAssertEqual(BuiltInThemes.neon.overlay.latencyOffset, OverlayConfig().latencyOffset, "the theme itself is untouched")
    }

    func testMatchesIgnoresSyncOffsetOnly() {
        let theme = BuiltInThemes.neon
        var overlay = theme.overlay
        overlay.latencyOffset = 0.7
        XCTAssertTrue(theme.matches(styleID: theme.styleID, overlay: overlay, lights: theme.lights, useArtworkColors: theme.useArtworkColors))

        overlay.glow = 0.1
        XCTAssertFalse(theme.matches(styleID: theme.styleID, overlay: overlay, lights: theme.lights, useArtworkColors: theme.useArtworkColors))
        XCTAssertFalse(theme.matches(styleID: "scroll", overlay: theme.overlay, lights: theme.lights, useArtworkColors: theme.useArtworkColors))
    }

    func testTolerantDecoding() throws {
        let json = #"{"id": "x", "name": "Sparse", "glow": "garbage"}"#
        let theme = try JSONDecoder().decode(Theme.self, from: Data(json.utf8))
        XCTAssertEqual(theme.styleID, "karaoke")
        XCTAssertEqual(theme.overlay, OverlayConfig())
        XCTAssertEqual(theme.lights, LightConfig())
    }

    func testIdentityIsRequired() {
        XCTAssertThrowsError(try JSONDecoder().decode(Theme.self, from: Data(#"{"name": "No id"}"#.utf8)))
    }
}

final class ThemeStoreTests: XCTestCase {
    private func custom(_ name: String = "Mine") -> Theme {
        var o = OverlayConfig()
        o.glow = 0.123
        return Theme(id: "", name: name, styleID: "wave", overlay: o)
    }

    func testAllIsBuiltInsPlusUserThemes() throws {
        let store = ThemeStore(directory: tempDir())
        XCTAssertEqual(store.all(), BuiltInThemes.all, "no folder yet is fine")
        let saved = try store.save(custom())
        XCTAssertEqual(store.all().count, BuiltInThemes.all.count + 1)
        XCTAssertEqual(store.all().last, saved)
    }

    func testSaveGivesUserIDsAndNeverReusesBuiltInIDs() throws {
        let store = ThemeStore(directory: tempDir())
        var t = custom()
        t.id = "builtin.neon"
        let saved = try store.save(t)
        XCTAssertTrue(saved.id.hasPrefix("user."))
        XCTAssertEqual(BuiltInThemes.theme(id: "builtin.neon")?.name, "Neon", "built-in is untouched")
    }

    func testSavingAgainUpdatesInPlace() throws {
        let store = ThemeStore(directory: tempDir())
        var saved = try store.save(custom("First"))
        saved.overlay.glow = 0.9
        try store.save(saved)
        XCTAssertEqual(store.userThemes().count, 1)
        XCTAssertEqual(store.userThemes().first?.overlay.glow, 0.9)
    }

    func testBlankNameBecomesUntitled() throws {
        XCTAssertEqual(try ThemeStore(directory: tempDir()).save(custom("   ")).name, "Untitled")
    }

    func testDelete() throws {
        let store = ThemeStore(directory: tempDir())
        let a = try store.save(custom("A")), b = try store.save(custom("B"))
        store.delete(id: a.id)
        XCTAssertEqual(store.userThemes().map(\.id), [b.id])
        store.delete(id: "builtin.neon")
        XCTAssertEqual(store.all().count, BuiltInThemes.all.count + 1, "built-ins can't be deleted")
    }

    func testCorruptFilesAreSkipped() throws {
        let dir = tempDir()
        let store = ThemeStore(directory: dir)
        let good = try store.save(custom("Good"))
        try Data("not json".utf8).write(to: dir.appendingPathComponent("broken.json"))
        try Data(#"{"version":1,"theme":{"name":"no id"}}"#.utf8).write(to: dir.appendingPathComponent("noid.json"))
        XCTAssertEqual(store.userThemes(), [good])
    }

    func testExportThenImportIntoAnotherStore() throws {
        let a = ThemeStore(directory: tempDir()), b = ThemeStore(directory: tempDir())
        let saved = try a.save(custom("Shared"))
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        try a.export(saved, to: file)

        let imported = try b.importTheme(from: file)
        XCTAssertEqual(imported.name, "Shared")
        XCTAssertNotEqual(imported.id, saved.id, "an import is always a new theme")
        XCTAssertEqual(imported.overlay, saved.overlay)
        XCTAssertEqual(imported.styleID, saved.styleID)
    }

    func testImportingTwiceNeverOverwritesOrDuplicatesNames() throws {
        let store = ThemeStore(directory: tempDir())
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        try store.export(custom("Twin"), to: file)

        let first = try store.importTheme(from: file), second = try store.importTheme(from: file)
        XCTAssertEqual(first.name, "Twin")
        XCTAssertEqual(second.name, "Twin 2")
        XCTAssertEqual(store.userThemes().count, 2)
    }

    func testImportRejectsBadFilesWithClearErrors() throws {
        let store = ThemeStore(directory: tempDir())
        func file(_ contents: String) throws -> URL {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
            try Data(contents.utf8).write(to: url)
            return url
        }
        XCTAssertThrowsError(try store.importTheme(from: file("hello"))) { XCTAssertEqual($0 as? ThemeError, .notATheme) }
        XCTAssertThrowsError(try store.importTheme(from: file(#"{"version": 99, "theme": {}}"#))) { XCTAssertEqual($0 as? ThemeError, .unsupportedVersion(99)) }
        XCTAssertThrowsError(try store.importTheme(from: URL(fileURLWithPath: "/nonexistent/theme.json"))) { XCTAssertEqual($0 as? ThemeError, .unreadable) }
        XCTAssertThrowsError(try store.importTheme(from: file(String(repeating: "x", count: 1_100_000)))) { XCTAssertEqual($0 as? ThemeError, .tooLarge) }
        XCTAssertTrue(store.userThemes().isEmpty, "failed imports leave nothing behind")
    }
}

final class ThemeCollectionTests: XCTestCase {
    private let themes = BuiltInThemes.all

    func testHasAtLeastTwentySixThemes() {
        XCTAssertGreaterThanOrEqual(themes.count, 26)
    }

    func testOriginalSixKeepTheirIDsAndComeFirst() {
        XCTAssertEqual(themes.prefix(6).map(\.id),
                       ["builtin.classic", "builtin.neon", "builtin.minimal", "builtin.terminal", "builtin.cinema", "builtin.pulse"])
    }

    func testIDsAndNamesAreUnique() {
        XCTAssertEqual(Set(themes.map(\.id)).count, themes.count)
        XCTAssertEqual(Set(themes.map(\.name)).count, themes.count)
    }

    func testEveryThemeHasItsOwnTypeface() {
        let families = themes.map(\.overlay.font.family)
        XCTAssertEqual(Set(families).count, families.count, "two themes share a font: \(families.sorted())")
        XCTAssertGreaterThanOrEqual(Set(families).count, 26)
    }

    func testLyraOriginalsAreUsedWhereTheMoodFits() {
        func font(_ id: String) -> String? { themes.first { $0.id == id }?.overlay.font.family }
        XCTAssertEqual(font("builtin.forge"), "LyraForge-Regular", "metal")
        XCTAssertEqual(font("builtin.thorn"), "LyraThorn-Regular", "gothic")
        XCTAssertEqual(font("builtin.razor"), "LyraBlade-Regular", "razor")
        XCTAssertEqual(font("builtin.neon"), "LyraNeonTube-Regular", "neon")
        XCTAssertEqual(font("builtin.arcade"), "LyraPixel-Regular", "pixel")
        XCTAssertEqual(font("builtin.stamp"), "LyraStencilOps-Regular", "stencil")
        XCTAssertEqual(font("builtin.blueprint"), "LyraCircuit-Regular", "techno")
        XCTAssertEqual(font("builtin.friendly"), "LyraMonolineRound-Regular", "soft")
    }

    func testTheHandDrawnFontsAreUsedWhereTheMoodFits() {
        func font(_ id: String) -> String? { themes.first { $0.id == id }?.overlay.font.family }
        XCTAssertEqual(font("builtin.punk"), "LyraBrush-Regular", "brush")
        XCTAssertEqual(font("builtin.street"), "LyraTag-Regular", "tag")
        XCTAssertEqual(font("builtin.cathedral"), "LyraGothic-Regular", "blackletter")
        XCTAssertEqual(font("builtin.diary"), "LyraHand-Regular", "handwriting")
        XCTAssertEqual(font("builtin.frontier"), "LyraSaloon-Regular", "wood type")
        XCTAssertEqual(font("builtin.candy"), "LyraBubble-Regular", "bubble")
        XCTAssertEqual(font("builtin.retro-wave"), "LyraRetro-Regular", "synthwave italic")
        XCTAssertEqual(font("builtin.katana"), "LyraBladeDrawn-Regular")
        XCTAssertEqual(font("builtin.foundry"), "LyraForgeDrawn-Regular")
        XCTAssertEqual(font("builtin.night-drive"), "LyraNeonDrawn-Regular")
        XCTAssertEqual(font("builtin.cabinet"), "LyraPixelDrawn-Regular")
        XCTAssertEqual(font("builtin.depot"), "LyraStencilDrawn-Regular")
    }

    /// <project>/Fonts, found from this file's path (LyraCore/Tests/LyraCoreTests/<file>).
    private var fontsDir: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fonts", isDirectory: true)
    }

    func testEveryLyraFontInTheFontsFolderIsTheFaceOfExactlyOneTheme() throws {
        // Real invariant over the folder: a font dropped into Fonts/ fails this until it has a theme.
        // (Font files are named after their PostScript name, e.g. LyraScript-Regular.ttf.)
        let files = try FileManager.default.contentsOfDirectory(atPath: fontsDir.path)
        let fontIDs = files.filter { $0.hasPrefix("Lyra") && $0.hasSuffix(".ttf") && !$0.contains(".tmp") }
            .map { ($0 as NSString).deletingPathExtension }
        XCTAssertGreaterThanOrEqual(fontIDs.count, 20, "Fonts/ should hold the Lyra fonts")
        let used = themes.map(\.overlay.font.family).filter { $0.hasPrefix("Lyra") }
        XCTAssertEqual(Set(used).count, used.count, "a Lyra font is the face of two themes")
        for id in fontIDs {
            XCTAssertEqual(used.filter { $0 == id }.count, 1, "\(id) must be the face of exactly one theme")
        }
        for id in used { XCTAssertTrue(fontIDs.contains(id), "a theme uses \(id), which is not in Fonts/") }
    }

    func testTheNewestDrawnFontsHaveTheirMoods() {
        func theme(_ id: String) -> Theme? { themes.first { $0.id == id } }
        XCTAssertEqual(theme("builtin.serenade")?.overlay.font.family, "LyraScript-Regular", "romantic ballad")
        XCTAssertEqual(theme("builtin.black-rose")?.overlay.font.family, "LyraThornDrawn-Regular", "dark romance")
        XCTAssertEqual(theme("builtin.mainframe")?.overlay.font.family, "LyraCircuitDrawn-Regular", "techno")
    }

    func testEveryStyleIDIsRegistered() {
        let registered = Set(LyricStyles.all.map(\.id))
        for theme in themes { XCTAssertTrue(registered.contains(theme.styleID), "\(theme.name) uses unknown style \(theme.styleID)") }
    }

    func testAllLyricStylesAreUsed() {
        let used = Set(themes.map(\.styleID))
        XCTAssertEqual(used, Set(LyricStyles.all.map(\.id)), "every lyric style should appear in at least one theme")
    }

    func testEntranceAndExitVarietyIsWide() {
        XCTAssertGreaterThanOrEqual(Set(themes.map(\.overlay.entrance)).count, 8)
        XCTAssertGreaterThanOrEqual(Set(themes.map(\.overlay.exit)).count, 4)
    }

    func testNoTwoThemesLookTheSame() {
        for (i, a) in themes.enumerated() {
            for b in themes[(i + 1)...] {
                let same = a.styleID == b.styleID && a.overlay == b.overlay && a.lights == b.lights && a.useArtworkColors == b.useArtworkColors
                XCTAssertFalse(same, "\(a.name) and \(b.name) are identical")
            }
        }
    }

    func testThemesMixLightingChoices() {
        XCTAssertTrue(themes.contains { !$0.lights.enabled }, "some themes should have no lights")
        XCTAssertTrue(themes.contains { $0.lights.enabled && $0.lights.useArtworkColors }, "some should follow the album")
        XCTAssertTrue(themes.contains { $0.lights.enabled && $0.lights.primary != nil }, "some should use their own colors")
    }

    func testValuesAreSane() {
        for theme in themes {
            let o = theme.overlay, l = theme.lights
            XCTAssertTrue((20...120).contains(o.font.size), "\(theme.name) font size \(o.font.size)")
            XCTAssertTrue((0...1.5).contains(o.glow), theme.name)
            XCTAssertTrue((0...1).contains(o.shadow), theme.name)
            XCTAssertTrue((0.05...1.5).contains(o.entranceDuration), theme.name)
            XCTAssertTrue((0...0.3).contains(o.entranceStagger), theme.name)
            XCTAssertTrue((0.05...0.9).contains(o.anchorY), theme.name)
            XCTAssertTrue((0...1).contains(l.intensity), theme.name)
            XCTAssertTrue((8...80).contains(l.thickness), theme.name)
        }
    }

    func testEveryThemeRoundTripsThroughJSON() throws {
        for theme in themes {
            let data = try JSONEncoder().encode(theme)
            XCTAssertEqual(try JSONDecoder().decode(Theme.self, from: data), theme, theme.name)
        }
    }
}
