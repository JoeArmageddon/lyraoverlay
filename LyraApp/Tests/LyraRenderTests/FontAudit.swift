import Foundation
import CoreText

/// The quality checks every font in the project's `Fonts/` folder must pass. `Scripts/install-fonts.sh`
/// runs the same checks (as an embedded Swift tool) before it copies a font in; this is the CI version.
enum FontAudit {
    /// <project>/Fonts, found from this file's path (LyraApp/Tests/LyraRenderTests/<file>).
    static let projectFonts: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fonts", isDirectory: true)

    static let requiredCharacters: [Character] = {
        var c: [Character] = []
        for u in UnicodeScalar("A").value...UnicodeScalar("Z").value { c.append(Character(UnicodeScalar(u)!)) }
        for u in UnicodeScalar("a").value...UnicodeScalar("z").value { c.append(Character(UnicodeScalar(u)!)) }
        c += Array("0123456789.,!?'\"-:;&()/#@%+=$*_~")
        c += Array("áàâäãåéèêëíìîïóòôöõúùûüñçýÿÁÀÂÄÃÅÉÈÊËÍÌÎÏÓÒÔÖÕÚÙÛÜÑÇÝ")
        return c
    }()

    struct Report {
        let url: URL
        var postScript = ""
        var family = ""
        var problems: [String] = []
    }

    /// Font files directly inside `directory` (never Fonts/drawn), without half-written `*.tmp*` files.
    static func fontFiles(in directory: URL = projectFonts) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { ["ttf", "otf"].contains($0.pathExtension.lowercased()) && !$0.lastPathComponent.contains(".tmp") && !$0.lastPathComponent.hasPrefix(".") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Everything that can be checked on one file alone (name uniqueness needs the whole folder).
    static func audit(_ url: URL) -> Report {
        var report = Report(url: url)
        guard let d = (CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor])?.first else {
            report.problems.append("CoreText cannot read it")
            return report
        }
        report.postScript = CTFontDescriptorCopyAttribute(d, kCTFontNameAttribute) as? String ?? ""
        report.family = CTFontDescriptorCopyAttribute(d, kCTFontFamilyNameAttribute) as? String ?? ""
        if report.postScript.isEmpty { report.problems.append("no PostScript name") }
        if report.family.isEmpty { report.problems.append("no family name") }

        let ct = CTFontCreateWithFontDescriptor(d, 1000, nil)
        if ((CTFontCopyName(ct, kCTFontCopyrightNameKey) as String?) ?? "").isEmpty { report.problems.append("no copyright string") }
        if !(((CTFontCopyName(ct, kCTFontLicenseNameKey) as String?) ?? "").contains("SIL Open Font License")) {
            report.problems.append("license text lacks the SIL Open Font License")
        }
        if CTFontGetUnitsPerEm(ct) != 1000 { report.problems.append("unitsPerEm \(CTFontGetUnitsPerEm(ct))") }
        if abs(CTFontGetAscent(ct) - 800) > 20 { report.problems.append("ascent \(CTFontGetAscent(ct))") }
        if abs(CTFontGetDescent(ct) - 200) > 20 { report.problems.append("descent \(CTFontGetDescent(ct))") }

        for ch in requiredCharacters {
            let units = Array(String(ch).utf16)
            var glyphs = [CGGlyph](repeating: 0, count: units.count)
            guard CTFontGetGlyphsForCharacters(ct, units, &glyphs, units.count) else { report.problems.append("missing glyph \(ch)"); continue }
            var advance = CGSize.zero
            CTFontGetAdvancesForGlyphs(ct, .horizontal, &glyphs, &advance, 1)
            if advance.width <= 0 { report.problems.append("non-positive advance for \(ch)") }
            if let box = CTFontCreatePathForGlyph(ct, glyphs[0], nil)?.boundingBoxOfPath, !box.isNull, !box.isEmpty {
                if box.maxY > 1002 { report.problems.append("\(ch) rises past 1.0 em (\(Int(box.maxY)))") }
                if box.minY < -402 { report.problems.append("\(ch) sinks below -0.4 em (\(Int(box.minY)))") }
            }
        }
        return report
    }
}

/// Makes a copy of a font file under a new, unique PostScript and family name, so import tests have a
/// font macOS has never heard of. Works by rewriting the names in the `name` table (same lengths).
enum TestFont {
    /// "LyraTag-Regular" (15 characters) and "Lyra Tag" (8) become random names of the same length.
    /// With `lyraTag` ("abc"), the names are "Lyraabc-Regular" and "Lyra abc", so the catalog treats the font as a Lyra one.
    static func makeUnique(in directory: URL, fileName: String? = nil, lyraTag: String? = nil) throws -> (url: URL, postScript: String, family: String) {
        let source = FontAudit.projectFonts.appendingPathComponent("LyraTag-Regular.ttf")
        var data = try Data(contentsOf: source)
        let tag = String((0..<6).map { _ in "abcdefghjkmnpqrstuvwxyz".randomElement()! })
        let postScript = lyraTag.map { "Lyra\($0)-Regular" } ?? "Q\(tag)-Regular"
        let family = lyraTag.map { "Lyra \($0)" } ?? "Q\(tag)z"
        func replace(_ old: String, _ new: String, utf16: Bool) {
            func bytes(_ s: String) -> Data { utf16 ? Data(s.utf16.flatMap { [UInt8($0 >> 8), UInt8($0 & 255)] }) : Data(s.utf8) }
            let x = bytes(old), y = bytes(new)
            var range = data.range(of: x)
            while let r = range {
                data.replaceSubrange(r, with: y)
                range = data.range(of: x, in: r.upperBound..<data.count)
            }
        }
        for utf16 in [false, true] {
            replace("LyraTag-Regular", postScript, utf16: utf16)
            replace("Lyra Tag", family, utf16: utf16)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(fileName ?? "\(family).ttf")
        try data.write(to: url)
        return (url, postScript, family)
    }
}
