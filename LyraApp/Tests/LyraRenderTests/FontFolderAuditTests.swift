import XCTest
import CoreText
@testable import LyraRender

/// Every font file in the project's Fonts/ folder, found by listing it, so fonts added later are covered
/// without touching this file.
final class FontFolderAuditTests: XCTestCase {
    private let files = FontAudit.fontFiles()

    func testTheFolderHoldsTheLyraFontsAndTheLicense() {
        XCTAssertGreaterThanOrEqual(files.count, 20)
        for name in ["LICENSE.txt", "README.md"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: FontAudit.projectFonts.appendingPathComponent(name).path), "Fonts/\(name) is missing")
        }
        let license = (try? String(contentsOf: FontAudit.projectFonts.appendingPathComponent("LICENSE.txt"), encoding: .utf8)) ?? ""
        XCTAssertTrue(license.contains("SIL Open Font License"))
    }

    func testEveryFontPassesTheAudit() {
        for url in files {
            let report = FontAudit.audit(url)
            XCTAssertTrue(report.problems.isEmpty, "\(url.lastPathComponent): \(report.problems.joined(separator: "; "))")
        }
    }

    func testPostScriptAndFamilyNamesAreUniqueAcrossTheFolder() {
        var postScript: [String: String] = [:], families: [String: String] = [:]
        for url in files {
            let report = FontAudit.audit(url)
            if let other = postScript[report.postScript] { XCTFail("\(url.lastPathComponent) and \(other) share the PostScript name \(report.postScript)") }
            if let other = families[report.family] { XCTFail("\(url.lastPathComponent) and \(other) share the family name \(report.family)") }
            postScript[report.postScript] = url.lastPathComponent
            families[report.family] = url.lastPathComponent
        }
    }

    func testFileNamesMatchPostScriptNamesAndLyraPrefix() {
        for url in files {
            let report = FontAudit.audit(url)
            XCTAssertEqual(url.deletingPathExtension().lastPathComponent, report.postScript, "name the file after its PostScript name")
            XCTAssertTrue(report.postScript.hasPrefix("Lyra"), "\(report.postScript) should start with Lyra")
            XCTAssertTrue(report.family.hasPrefix("Lyra "), "\(report.family) should start with \"Lyra \"")
        }
    }

    func testCopyrightNamesTheProject() throws {
        for url in files {
            let d = try XCTUnwrap((CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor])?.first)
            let ct = CTFontCreateWithFontDescriptor(d, 20, nil)
            let copyright = (CTFontCopyName(ct, kCTFontCopyrightNameKey) as String?) ?? ""
            XCTAssertTrue(copyright.contains("Lyra") && copyright.contains("2026"), "\(url.lastPathComponent): \(copyright)")
        }
    }

    func testTheAuditActuallyCatchesProblems() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("lyra-audit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let junk = temp.appendingPathComponent("Junk.ttf")
        try Data("not a font".utf8).write(to: junk)
        XCTAssertFalse(FontAudit.audit(junk).problems.isEmpty)
        // A system font has the wrong metrics, no OFL text and probably missing glyphs.
        let system = URL(fileURLWithPath: "/System/Library/Fonts/Supplemental/Arial.ttf")
        if FileManager.default.fileExists(atPath: system.path) {
            let problems = FontAudit.audit(system).problems.joined(separator: " ")
            XCTAssertTrue(problems.contains("unitsPerEm") && problems.contains("SIL Open Font License"), problems)
        }
        // Half-written files are not listed.
        try FileManager.default.copyItem(at: FontAudit.projectFonts.appendingPathComponent("LyraTag-Regular.ttf"), to: temp.appendingPathComponent("LyraTag-Regular.tmp.ttf"))
        XCTAssertEqual(FontAudit.fontFiles(in: temp).map(\.lastPathComponent), ["Junk.ttf"])
    }
}
