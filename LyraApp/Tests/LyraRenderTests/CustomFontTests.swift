import XCTest
import AppKit
import CoreText
import LyraCore
@testable import LyraRender

/// The "add custom fonts" feature: listing, importing several files, removing, and everything around it.
/// Every test works in a temp folder through `directoryOverride`, never the real Application Support.
final class CustomFontTests: XCTestCase {
    private var root: URL!
    private var source: URL { root.appendingPathComponent("Downloads", isDirectory: true) }

    override func setUpWithError() throws {
        try super.setUpWithError()
        FontCatalog.registerBundledFonts()
        root = FileManager.default.temporaryDirectory.appendingPathComponent("lyra-custom-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        FontCatalog.directoryOverride = root.appendingPathComponent("UserFonts", isDirectory: true)
    }

    override func tearDownWithError() throws {
        for font in FontCatalog.userFonts() { try? FontCatalog.removeUserFont(font) }
        FontCatalog.directoryOverride = nil
        try? FileManager.default.removeItem(at: root)
        try super.tearDownWithError()
    }

    private func imported(_ count: Int = 1) throws -> [(url: URL, postScript: String, family: String)] {
        let made = try (0..<count).map { _ in try TestFont.makeUnique(in: source) }
        XCTAssertTrue(FontCatalog.importFonts(urls: made.map(\.url)).allSatisfy(\.succeeded))
        return made
    }

    // MARK: userFonts()

    func testUserFontsIsEmptyBeforeAnyImport() {
        XCTAssertEqual(FontCatalog.userFonts(), [])
    }

    func testUserFontsDescribeEachImportedFile() throws {
        let made = try imported()
        let fonts = FontCatalog.userFonts()
        XCTAssertEqual(fonts.count, 1)
        let font = try XCTUnwrap(fonts.first)
        XCTAssertEqual(font.fileName, made[0].url.lastPathComponent)
        XCTAssertEqual(font.id, font.fileName)
        XCTAssertEqual(font.families, [made[0].family])
        XCTAssertEqual(font.postScriptNames, [made[0].postScript])
        XCTAssertEqual(font.displayName, made[0].family)
        XCTAssertEqual(font.fontID, made[0].postScript)
        XCTAssertGreaterThan(font.byteCount, 5_000)
        XCTAssertTrue(font.isRegistered)
        XCTAssertEqual(font.url.deletingLastPathComponent().standardizedFileURL, FontCatalog.userFontsDirectory.standardizedFileURL)
    }

    func testUserFontsAreSortedByNameAndListABrokenFileSoItCanBeRemoved() throws {
        _ = try imported(3)
        try Data("junk".utf8).write(to: FontCatalog.userFontsDirectory.appendingPathComponent("broken.ttf"))
        try Data("x".utf8).write(to: FontCatalog.userFontsDirectory.appendingPathComponent("notes.txt"))
        let fonts = FontCatalog.userFonts()
        XCTAssertEqual(fonts.count, 4, "three fonts and the broken file; the .txt is not a font file")
        let names = fonts.map(\.displayName)
        XCTAssertEqual(names, names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
        let broken = try XCTUnwrap(fonts.first { $0.fileName == "broken.ttf" })
        XCTAssertTrue(broken.postScriptNames.isEmpty)
        XCTAssertFalse(broken.isRegistered)
        XCTAssertNoThrow(try FontCatalog.removeUserFont(broken))
    }

    func testImportedFontsAreAvailableWithoutARestart() throws {
        let made = try imported()
        XCTAssertTrue(FontCatalog.isInstalled(made[0].postScript))
        XCTAssertTrue(FontCatalog.families().contains(made[0].family), "the family list (used by the pickers) includes it at once")
        let ct = FontResolver.ctFont(FontSpec(family: made[0].postScript, size: 30))
        XCTAssertEqual(CTFontCopyPostScriptName(ct) as String, made[0].postScript, "resolves to itself, not the system font")
        let picker = FontPicker.groups(query: "", chip: .all, installed: FontCatalog.families(), current: "System")
        XCTAssertEqual(picker.first?.title, FontPicker.myFontsTitle)
        XCTAssertEqual(picker.first?.rows.first?.id, made[0].postScript)
    }

    // MARK: importFonts(urls:)

    func testImportingSeveralFilesReportsEachOne() throws {
        let good1 = try TestFont.makeUnique(in: source), good2 = try TestFont.makeUnique(in: source)
        let text = source.appendingPathComponent("notes.txt"); try Data("hello".utf8).write(to: text)
        let fake = source.appendingPathComponent("fake.otf"); try Data("not a font".utf8).write(to: fake)
        let missing = source.appendingPathComponent("missing.ttf")
        let lyra = FontAudit.projectFonts.appendingPathComponent("LyraTag-Regular.ttf")

        let results = FontCatalog.importFonts(urls: [good1.url, text, fake, missing, lyra, good2.url])
        XCTAssertEqual(results.map(\.sourceName), [good1.url, text, fake, missing, lyra, good2.url].map(\.lastPathComponent), "one result per file, in order")
        XCTAssertEqual(results.map(\.succeeded), [true, false, false, false, false, true])
        XCTAssertEqual(results[0].families, [good1.family])
        XCTAssertEqual(results[0].fontID, good1.postScript)
        XCTAssertEqual(results[0].storedFileName, good1.url.lastPathComponent)
        XCTAssertEqual(results[1].error, .unsupportedType("notes.txt"))
        XCTAssertEqual(results[2].error, .notAFont("fake.otf"))
        XCTAssertEqual(results[3].error, .unreadable("missing.ttf"))
        guard case .duplicate(_, let owner)? = results[4].error else { return XCTFail("a Lyra font is a duplicate") }
        XCTAssertTrue(owner.contains("ships with Lyra"), owner)
        XCTAssertEqual(FontCatalog.userFonts().count, 2, "only the two good fonts were copied")
        for r in results { XCTAssertEqual(r.succeeded, r.error == nil) }
    }

    func testAFontMacOSAlreadyHasIsReportedAsADuplicate() throws {
        let system = ["/System/Library/Fonts/Supplemental/Arial.ttf", "/System/Library/Fonts/Supplemental/Courier New.ttf",
                      "/System/Library/Fonts/Supplemental/Georgia.ttf"].first { FileManager.default.fileExists(atPath: $0) }
        let path = try XCTUnwrap(system, "no known system .ttf on this Mac")
        let result = FontCatalog.importOne(URL(fileURLWithPath: path))
        guard case .duplicate(let name, let owner)? = result.error else { return XCTFail("expected a duplicate, got \(String(describing: result.error))") }
        XCTAssertEqual(name, (path as NSString).lastPathComponent)
        XCTAssertTrue(owner.contains("macOS already has"), owner)
        XCTAssertTrue(result.error?.errorDescription?.contains("already available") == true)
        XCTAssertEqual(FontCatalog.userFonts(), [], "nothing is copied for a duplicate")
    }

    func testReimportingTheSameFileSaysYouAlreadyAddedIt() throws {
        let made = try imported()
        let again = FontCatalog.importOne(made[0].url)
        guard case .duplicate(_, let owner)? = again.error else { return XCTFail("expected a duplicate") }
        XCTAssertTrue(owner.contains("you already added it"), owner)
        XCTAssertEqual(FontCatalog.userFonts().count, 1)
    }

    func testTwoDifferentFontsWithTheSameFileNameNeverOverwriteEachOther() throws {
        let a = try TestFont.makeUnique(in: source.appendingPathComponent("a"), fileName: "Same.ttf")
        let b = try TestFont.makeUnique(in: source.appendingPathComponent("b"), fileName: "Same.ttf")
        let results = FontCatalog.importFonts(urls: [a.url, b.url])
        XCTAssertTrue(results.allSatisfy(\.succeeded))
        XCTAssertEqual(results.compactMap(\.storedFileName), ["Same.ttf", "Same-1.ttf"])
    }

    func testImportErrorsAreLocalizedAndNameTheFile() {
        let all: [FontImportError] = [.unreadable("a.ttf"), .unsupportedType("a.ttf"), .notAFont("a.ttf"), .registrationFailed("a.ttf"),
                                      .duplicate("a.ttf", "it ships with Lyra"), .outsideUserFolder("a.ttf"), .notInstalled("a.ttf")]
        for error in all { XCTAssertTrue(error.errorDescription?.contains("a.ttf") == true, "\(error)") }
        XCTAssertEqual(Set(all.compactMap(\.errorDescription)).count, all.count, "each error reads differently")
    }

    func testTheSummaryLineIsReadable() throws {
        XCTAssertEqual(ImportResult.summary([]), "No fonts were added.")
        let made = try TestFont.makeUnique(in: source)
        let text = source.appendingPathComponent("a.txt"); try Data().write(to: text)
        let one = FontCatalog.importFonts(urls: [made.url])
        XCTAssertEqual(ImportResult.summary(one), "Added \(made.family).")
        let mixed = ImportResult.summary(FontCatalog.importFonts(urls: [text, text]))
        XCTAssertTrue(mixed.contains("isn't a font file") && mixed.contains("1 more"), mixed)
    }

    // MARK: removeUserFont

    func testRemovingDeletesTheFileAndUnloadsTheFont() throws {
        let made = try imported(2)
        let font = try XCTUnwrap(FontCatalog.userFonts().first { $0.fontID == made[0].postScript })
        try FontCatalog.removeUserFont(font)
        XCTAssertFalse(FileManager.default.fileExists(atPath: font.url.path))
        XCTAssertEqual(FontCatalog.userFonts().count, 1, "the other font is untouched")
        XCTAssertEqual(FontCatalog.userFonts().first?.fontID, made[1].postScript)
        XCTAssertFalse(FontCatalog.isInstalled(made[0].postScript), "unregistered for this process")
        XCTAssertTrue(FontCatalog.isInstalled(made[1].postScript))
    }

    func testRemovingRefusesAnythingOutsideTheUserFolder() throws {
        _ = try imported()
        let outside = source.appendingPathComponent("keep.ttf")
        try Data("x".utf8).write(to: outside)
        let lyra = FontAudit.projectFonts.appendingPathComponent("LyraTag-Regular.ttf")
        for url in [outside, lyra,
                    FontCatalog.userFontsDirectory.appendingPathComponent("../Downloads/keep.ttf"),
                    FontCatalog.userFontsDirectory, FontCatalog.userFontsDirectory.deletingLastPathComponent()] {
            XCTAssertThrowsError(try FontCatalog.removeUserFont(at: url), url.path) { error in
                guard case .outsideUserFolder? = error as? FontImportError else { return XCTFail("\(error) for \(url.path)") }
            }
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: lyra.path), "Lyra's own fonts are never deleted")
        XCTAssertEqual(FontCatalog.userFonts().count, 1)
    }

    func testRemovingAFileThatIsGoneIsAClearError() {
        let ghost = FontCatalog.userFontsDirectory.appendingPathComponent("ghost.ttf")
        XCTAssertThrowsError(try FontCatalog.removeUserFont(at: ghost)) { XCTAssertEqual($0 as? FontImportError, .notInstalled("ghost.ttf")) }
    }

    func testRemovingASymlinkThatPointsOutsideIsRefusedAndTheTargetSurvives() throws {
        try FileManager.default.createDirectory(at: FontCatalog.userFontsDirectory, withIntermediateDirectories: true)
        let target = source.appendingPathComponent("precious.ttf"); try Data("x".utf8).write(to: target)
        let link = FontCatalog.userFontsDirectory.appendingPathComponent("link.ttf")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        XCTAssertThrowsError(try FontCatalog.removeUserFont(at: link))
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
    }

    func testAThemeOrSettingThatNamesARemovedFontFallsBackToTheSystemFont() throws {
        let made = try imported()
        let spec = FontSpec(family: made[0].postScript, size: 40)
        XCTAssertEqual(CTFontCopyPostScriptName(FontResolver.ctFont(spec)) as String, made[0].postScript)
        XCTAssertNil(FontPicker.missingFontNote(current: made[0].postScript))
        try FontCatalog.removeUserFont(try XCTUnwrap(FontCatalog.userFonts().first))
        let fallback = CTFontCopyPostScriptName(FontResolver.ctFont(spec)) as String
        XCTAssertNotEqual(fallback, made[0].postScript, "no crash, no blank: the system font draws instead")
        XCTAssertNotNil(TextRasterizer.rasterize("Hello", font: spec, scale: 1))
        XCTAssertTrue(FontPicker.missingFontNote(current: made[0].postScript)?.contains(made[0].postScript) == true)
    }

    // MARK: Change notification, folder, panel, drop

    func testChangesArePostedSoOpenPickersRefresh() throws {
        let imported = expectation(forNotification: FontCatalog.didChangeNotification, object: nil)
        let made = try TestFont.makeUnique(in: source)
        FontCatalog.importFonts(urls: [made.url])
        wait(for: [imported], timeout: 2)

        let removed = expectation(forNotification: FontCatalog.didChangeNotification, object: nil)
        try FontCatalog.removeUserFont(try XCTUnwrap(FontCatalog.userFonts().first))
        wait(for: [removed], timeout: 2)

        let quiet = expectation(forNotification: FontCatalog.didChangeNotification, object: nil)
        quiet.isInverted = true
        FontCatalog.importFonts(urls: [source.appendingPathComponent("nothing.ttf")])
        wait(for: [quiet], timeout: 0.3)
    }

    func testRevealCreatesTheFolderAndOpensIt() {
        var opened: [URL] = []
        XCTAssertFalse(FileManager.default.fileExists(atPath: FontCatalog.userFontsDirectory.path))
        FontCatalog.revealUserFontsFolder { opened.append($0) }
        XCTAssertEqual(opened, [FontCatalog.userFontsDirectory])
        XCTAssertTrue(FileManager.default.fileExists(atPath: FontCatalog.userFontsDirectory.path))
    }

    func testTheRealFolderIsUnderApplicationSupport() {
        FontCatalog.directoryOverride = nil
        XCTAssertTrue(FontCatalog.userFontsDirectory.path.hasSuffix("Application Support/Lyra/Fonts"))
        FontCatalog.directoryOverride = root.appendingPathComponent("UserFonts", isDirectory: true)
    }

    @MainActor func testTheOpenPanelAllowsSeveralFontFilesOnly() {
        let panel = FontCatalog.makeFontOpenPanel()
        XCTAssertTrue(panel.allowsMultipleSelection)
        XCTAssertFalse(panel.canChooseDirectories)
        XCTAssertTrue(panel.canChooseFiles)
        let extensions = Set(panel.allowedContentTypes.flatMap { $0.tags[.filenameExtension] ?? [] })
        XCTAssertTrue(extensions.isSuperset(of: ["ttf", "otf", "ttc", "otc"]), "\(extensions)")
    }

    func testDroppedFileURLsAreCollectedAndOthersIgnored() throws {
        let a = try TestFont.makeUnique(in: source), b = try TestFont.makeUnique(in: source)
        let providers = [NSItemProvider(object: a.url as NSURL), NSItemProvider(object: b.url as NSURL), NSItemProvider(object: "just text" as NSString)]
        let done = expectation(description: "collected")
        var collected: [URL] = []
        FontPicker.fileURLs(from: providers) { collected = $0; done.fulfill() }
        wait(for: [done], timeout: 3)
        XCTAssertEqual(Set(collected.map(\.lastPathComponent)), [a.url.lastPathComponent, b.url.lastPathComponent])
        XCTAssertTrue(FontCatalog.importFonts(urls: collected).allSatisfy(\.succeeded), "a drop imports like the button does")
    }

    // MARK: Picker state

    func testPickerGroupsWithCustomFonts() throws {
        let made = try imported(2)
        let user = FontCatalog.userFonts()
        func groups(query: String = "", chip: FontPicker.Chip = .all, current: String = "System") -> [FontPicker.Group] {
            FontPicker.groups(query: query, chip: chip, installed: FontCatalog.families(), current: current, userFonts: user)
        }
        XCTAssertEqual(groups().first?.title, "My Fonts", "your fonts lead the full list")
        XCTAssertEqual(Set(groups().first?.rows.compactMap(\.userFileName) ?? []), Set(user.map(\.fileName)), "rows carry their file for Remove / Show in Finder")
        XCTAssertEqual(groups(chip: .myFonts).map(\.title), ["My Fonts"])
        XCTAssertEqual(groups(chip: .category(.serif)).map(\.title), ["Serif"], "other chips hide My Fonts")
        XCTAssertEqual(groups(query: made[0].family.lowercased(), chip: .myFonts).first?.rows.map(\.id), [made[0].postScript])
        XCTAssertEqual(groups(query: "zzz-no-such", chip: .myFonts), [])
        let all = groups().flatMap(\.rows).map(\.id)
        XCTAssertEqual(Set(all).count, all.count, "an imported font is not repeated under All installed fonts")
        XCTAssertFalse(groups().last?.rows.contains { $0.name == made[0].family } ?? false)
        XCTAssertNil(groups().flatMap(\.rows).first { $0.id == "LyraForge-Regular" }?.userFileName)
    }

    func testACopyOfAFontThatShipsWithLyraIsNotListedUnderMyFonts() {
        let copy = UserFont(fileName: "LyraTag-Regular.ttf", url: FontCatalog.userFontsDirectory.appendingPathComponent("LyraTag-Regular.ttf"),
                            families: ["Lyra Tag"], postScriptNames: ["LyraTag-Regular"], byteCount: 1, isRegistered: true)
        let g = FontPicker.groups(query: "", chip: .all, installed: FontCatalog.families(), current: "System", userFonts: [copy])
        XCTAssertFalse(g.contains { $0.title == FontPicker.myFontsTitle })
        XCTAssertEqual(g.flatMap(\.rows).filter { $0.id == "LyraTag-Regular" }.count, 1)
    }

    func testPickerCopyDescribesWhereFontsAreStored() {
        XCTAssertTrue(FontPicker.storageHint.contains("Application Support/Lyra/Fonts"))
        XCTAssertTrue(FontPicker.emptyStateText.contains("Add Custom Font"))
    }
}
