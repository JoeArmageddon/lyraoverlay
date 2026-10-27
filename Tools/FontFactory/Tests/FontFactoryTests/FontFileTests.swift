import XCTest
import CoreText
@testable import FontFactoryCore

/// A small independent reader for the files the writer produces, so the tests check the bytes
/// rather than trusting the writer's own bookkeeping.
private struct SFNT {
    let data: [UInt8]
    struct Table { var tag: String; var checksum: UInt32; var offset: Int; var length: Int }
    var tables: [Table] = []

    init(_ d: Data) {
        data = [UInt8](d)
        let n = Int(u16(4))
        for i in 0..<n {
            let at = 12 + i * 16
            let tag = String(decoding: data[at..<at + 4], as: UTF8.self)
            tables.append(Table(tag: tag, checksum: u32(at + 4), offset: Int(u32(at + 8)), length: Int(u32(at + 12))))
        }
    }

    func u16(_ at: Int) -> UInt16 { UInt16(data[at]) << 8 | UInt16(data[at + 1]) }
    func i16(_ at: Int) -> Int { Int(Int16(bitPattern: u16(at))) }
    func u32(_ at: Int) -> UInt32 { UInt32(u16(at)) << 16 | UInt32(u16(at + 2)) }
    func table(_ tag: String) -> Table { tables.first { $0.tag == tag }! }

    var glyphCount: Int { Int(u16(table("maxp").offset + 4)) }

    func glyphRange(_ gid: Int) -> Range<Int> {
        let loca = table("loca").offset, glyf = table("glyf").offset
        return (glyf + Int(u32(loca + gid * 4)))..<(glyf + Int(u32(loca + (gid + 1) * 4)))
    }

    struct Decoded {
        var contours: [[(x: Int, y: Int)]]
        var header: (minX: Int, minY: Int, maxX: Int, maxY: Int)
    }

    /// Decodes a simple glyph the way a rasterizer would.
    func glyph(_ gid: Int) -> Decoded? {
        let range = glyphRange(gid)
        guard !range.isEmpty else { return nil }
        var p = range.lowerBound
        let n = i16(p); p += 2
        let header = (minX: i16(p), minY: i16(p + 2), maxX: i16(p + 4), maxY: i16(p + 6)); p += 8
        var ends: [Int] = []
        for _ in 0..<n { ends.append(Int(u16(p))); p += 2 }
        let total = (ends.last ?? -1) + 1
        let instructions = Int(u16(p)); p += 2 + instructions
        var flags: [UInt8] = []
        while flags.count < total {
            let f = data[p]; p += 1
            flags.append(f)
            if f & 0x08 != 0 { let repeats = Int(data[p]); p += 1; flags += Array(repeating: f, count: repeats) }
        }
        var xs: [Int] = [], ys: [Int] = []
        var v = 0
        for f in flags {
            if f & 0x02 != 0 { let d = Int(data[p]); p += 1; v += f & 0x10 != 0 ? d : -d }
            else if f & 0x10 == 0 { v += i16(p); p += 2 }
            xs.append(v)
        }
        v = 0
        for f in flags {
            if f & 0x04 != 0 { let d = Int(data[p]); p += 1; v += f & 0x20 != 0 ? d : -d }
            else if f & 0x20 == 0 { v += i16(p); p += 2 }
            ys.append(v)
        }
        var contours: [[(x: Int, y: Int)]] = []
        var start = 0
        for e in ends { contours.append((start...e).map { (xs[$0], ys[$0]) }); start = e + 1 }
        return Decoded(contours: contours, header: header)
    }

    /// Format 4 cmap lookup.
    func glyphID(for code: UInt16) -> Int {
        let cmap = table("cmap").offset
        let sub = cmap + Int(u32(cmap + 8))
        let segX2 = Int(u16(sub + 6))
        let ends = sub + 14, starts = ends + segX2 + 2, deltas = starts + segX2
        for s in 0..<(segX2 / 2) {
            let end = u16(ends + s * 2), start = u16(starts + s * 2)
            if code >= start && code <= end { return (Int(code) + i16(deltas + s * 2)) & 0xFFFF }
        }
        return 0
    }

    func name(_ id: Int) -> String? {
        let t = table("name").offset
        let count = Int(u16(t + 2)), stringStart = t + Int(u16(t + 4))
        for i in 0..<count {
            let r = t + 6 + i * 12
            guard u16(r) == 3, Int(u16(r + 6)) == id else { continue }
            let len = Int(u16(r + 8)), off = Int(u16(r + 10))
            let bytes = data[(stringStart + off)..<(stringStart + off + len)]
            var units: [UInt16] = []
            var it = bytes.makeIterator()
            while let hi = it.next(), let lo = it.next() { units.append(UInt16(hi) << 8 | UInt16(lo)) }
            return String(decoding: units, as: UTF16.self)
        }
        return nil
    }
}

private func checksum(_ bytes: ArraySlice<UInt8>) -> UInt32 {
    var sum: UInt32 = 0
    let arr = Array(bytes)
    var i = 0
    while i < arr.count {
        var w: UInt32 = 0
        for k in 0..<4 { w = (w << 8) | UInt32(i + k < arr.count ? arr[i + k] : 0) }
        sum = sum &+ w
        i += 4
    }
    return sum
}

/// Every font is generated once and reused, since generation is the slow part.
private let results: [FontFactory.Result] = Styles.all.map { FontFactory.make($0) }

final class FontFileTests: XCTestCase {
    func testEveryStyleHasAllRequiredCharacters() {
        for r in results { XCTAssertTrue(r.missing.isEmpty, "\(r.style.name) lacks \(String(r.missing))") }
    }

    func testNamesAreUnique() {
        XCTAssertEqual(Set(results.map { $0.style.postScriptName }).count, results.count)
        XCTAssertEqual(Set(results.map { $0.style.family }).count, results.count)
        XCTAssertGreaterThanOrEqual(results.count, 5, "ship at least five good fonts")
    }

    func testTableDirectoryIsWellFormed() {
        for r in results {
            let f = SFNT(r.data)
            XCTAssertEqual(f.u32(0), 0x00010000, r.style.name)
            XCTAssertEqual(f.tables.map(\.tag), ["OS/2", "cmap", "glyf", "head", "hhea", "hmtx", "loca", "maxp", "name", "post"], r.style.name)
            XCTAssertEqual(f.tables.map(\.tag), f.tables.map(\.tag).sorted(), "directory must be sorted by tag")
            for t in f.tables {
                XCTAssertEqual(t.offset % 4, 0, "\(r.style.name) \(t.tag) offset not 4-aligned")
                XCTAssertLessThanOrEqual(t.offset + t.length, f.data.count, "\(r.style.name) \(t.tag) runs past the file")
            }
            // Fields the binary search over the directory depends on.
            XCTAssertEqual(f.u16(4), 10)
            XCTAssertEqual(f.u16(6), 128)     // searchRange = 16 * 2^3
            XCTAssertEqual(f.u16(8), 3)       // entrySelector
            XCTAssertEqual(f.u16(10), 32)     // rangeShift = 160 - 128
        }
    }

    func testChecksumsAreCorrect() {
        for r in results {
            let f = SFNT(r.data)
            for t in f.tables {
                var bytes = Array(f.data[t.offset..<t.offset + t.length])
                if t.tag == "head" { for i in 8..<12 { bytes[i] = 0 } }   // computed with the adjustment zeroed
                XCTAssertEqual(checksum(bytes[...]), t.checksum, "\(r.style.name) \(t.tag) checksum")
            }
            XCTAssertEqual(checksum(f.data[...]), 0xB1B0AFBA, "\(r.style.name) whole-file checksum")
        }
    }

    func testHeadMaxpHheaAgree() {
        for r in results {
            let f = SFNT(r.data)
            let head = f.table("head").offset
            XCTAssertEqual(f.u32(head + 12), 0x5F0F3CF5, "magic")
            XCTAssertEqual(f.u16(head + 18), 1000, "unitsPerEm")
            XCTAssertEqual(f.i16(head + 50), 1, "long loca")
            let n = f.glyphCount
            XCTAssertEqual(n, r.glyphCount)
            XCTAssertEqual(Int(f.u16(f.table("hhea").offset + 34)), n, "numberOfHMetrics")
            XCTAssertEqual(f.table("hmtx").length, n * 4)
            XCTAssertEqual(f.table("loca").length, (n + 1) * 4)
        }
    }

    func testLocaIsMonotonicAndCoversGlyf() {
        for r in results {
            let f = SFNT(r.data)
            var last = 0
            let loca = f.table("loca").offset
            for g in 0...f.glyphCount {
                let o = Int(f.u32(loca + g * 4))
                XCTAssertGreaterThanOrEqual(o, last, "\(r.style.name) loca not monotonic at \(g)")
                XCTAssertEqual(o % 4, 0)
                last = o
            }
            XCTAssertEqual(last, f.table("glyf").length, "\(r.style.name) loca end must equal glyf length")
        }
    }

    func testGlyphHeadersMatchTheirPoints() {
        for r in results {
            let f = SFNT(r.data)
            for gid in 0..<f.glyphCount {
                guard let g = f.glyph(gid) else { continue }
                let pts = g.contours.flatMap { $0 }
                XCTAssertFalse(pts.isEmpty)
                XCTAssertEqual(g.header.minX, pts.map(\.x).min(), "\(r.style.name) glyph \(gid)")
                XCTAssertEqual(g.header.maxX, pts.map(\.x).max(), "\(r.style.name) glyph \(gid)")
                XCTAssertEqual(g.header.minY, pts.map(\.y).min(), "\(r.style.name) glyph \(gid)")
                XCTAssertEqual(g.header.maxY, pts.map(\.y).max(), "\(r.style.name) glyph \(gid)")
            }
        }
    }

    func testCmapMapsEveryRequiredCharacterToARealGlyph() {
        for r in results {
            let f = SFNT(r.data)
            for ch in Skeleton.required {
                let code = ch.unicodeScalars.first!.value
                let gid = f.glyphID(for: UInt16(code))
                XCTAssertGreaterThan(gid, 0, "\(r.style.name): U+\(String(code, radix: 16)) not mapped")
                XCTAssertLessThan(gid, f.glyphCount)
                let hasOutline = f.glyph(gid) != nil
                if ch == " " { XCTAssertFalse(hasOutline, "space has no outline") }
                else { XCTAssertTrue(hasOutline, "\(r.style.name): \(ch) has no outline") }
            }
            XCTAssertEqual(f.glyphID(for: 0x4E2D), 0, "unmapped characters fall back to .notdef")
        }
    }

    func testEveryOutlineIsClockwiseSoOverlapsUnion() {
        for r in results {
            let f = SFNT(r.data)
            for gid in 1..<f.glyphCount {
                guard let g = f.glyph(gid) else { continue }
                for c in g.contours {
                    var area = 0
                    for i in 0..<c.count { let p = c[i], q = c[(i + 1) % c.count]; area += p.x * q.y - q.x * p.y }
                    XCTAssertLessThanOrEqual(area, 0, "\(r.style.name) glyph \(gid) has a counter-clockwise contour; overlaps would cancel")
                }
            }
        }
    }

    func testNotdefIsAFrameWithAHole() {
        for r in results {
            let g = SFNT(r.data).glyph(0)
            XCTAssertEqual(g?.contours.count, 2, r.style.name)
        }
    }

    func testMetricsAreSane() {
        for r in results {
            let f = SFNT(r.data)
            let hmtx = f.table("hmtx").offset
            for gid in 0..<f.glyphCount {
                let adv = Int(f.u16(hmtx + gid * 4))
                XCTAssertGreaterThan(adv, 0, "\(r.style.name) glyph \(gid) has no advance")
                XCTAssertLessThan(adv, 2000)
                if let g = f.glyph(gid) {
                    XCTAssertEqual(f.i16(hmtx + gid * 4 + 2), g.header.minX, "lsb must equal xMin")
                    XCTAssertLessThanOrEqual(g.header.maxX, adv + 100, "\(r.style.name) glyph \(gid) hangs far past its advance")
                    XCTAssertGreaterThan(g.header.minX, -100)
                    XCTAssertTrue((-400...1100).contains(g.header.minY) && g.header.maxY <= 1100, "\(r.style.name) glyph \(gid) y-range \(g.header.minY)...\(g.header.maxY)")
                }
            }
            let os2 = f.table("OS/2")
            XCTAssertEqual(os2.length, 96)
            XCTAssertEqual(f.u16(os2.offset), 4)
            XCTAssertEqual(f.i16(f.table("hhea").offset + 4), 800)
            XCTAssertEqual(f.i16(f.table("hhea").offset + 6), -200)
        }
    }

    func testCapitalsAreAboutCapHeightAndLowercaseIsShorter() {
        for r in results {
            let f = SFNT(r.data)
            func height(_ ch: Character) -> Int {
                let g = f.glyph(f.glyphID(for: UInt16(ch.unicodeScalars.first!.value)))!
                return g.header.maxY - g.header.minY
            }
            // "E" has no vertical stem ends, so spiked or tapered terminals can't poke past the cap
            // line: its height is the true cap height (700, plus a hair for serrations).
            let cap = height("E")
            XCTAssertTrue((680...780).contains(cap), "\(r.style.name) E is \(cap) tall")
            // Stems must reach the cap line too, not stop a stroke-width short.
            XCTAssertGreaterThanOrEqual(height("H"), 680, "\(r.style.name) H stems fall short of the cap line")
            if !r.style.isPixel { XCTAssertLessThan(height("e"), cap, "\(r.style.name) lowercase should be small capitals") }
        }
    }

    func testNameTableCarriesTheLicense() {
        for r in results {
            let f = SFNT(r.data)
            XCTAssertEqual(f.name(1), r.style.family)
            XCTAssertEqual(f.name(6), r.style.postScriptName)
            XCTAssertEqual(f.name(2), "Regular")
            XCTAssertTrue(f.name(0)?.contains("2026 Lyra project") == true)
            XCTAssertTrue(f.name(13)?.contains("SIL Open Font License") == true)
            XCTAssertEqual(f.name(14), "https://openfontlicense.org")
        }
    }

    func testGenerationIsDeterministic() {
        // The same inputs must give byte-identical fonts, so regenerating never produces a spurious diff.
        for style in [Styles.forge, Styles.thorn] {
            XCTAssertEqual(FontFactory.make(style).data, FontFactory.make(style).data, style.name)
        }
    }

    // MARK: - CoreText

    func testCoreTextLoadsEveryFontAndDrawsEveryCharacter() throws {
        for r in results {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(r.style.fileName)")
            try r.data.write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }

            let descriptors = try XCTUnwrap(CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor], r.style.name)
            XCTAssertEqual(descriptors.count, 1)
            let ps = CTFontDescriptorCopyAttribute(descriptors[0], kCTFontNameAttribute) as? String
            XCTAssertEqual(ps, r.style.postScriptName)
            let family = CTFontDescriptorCopyAttribute(descriptors[0], kCTFontFamilyNameAttribute) as? String
            XCTAssertEqual(family, r.style.family)

            let font = CTFontCreateWithFontDescriptor(descriptors[0], 100, nil)
            for ch in Skeleton.required {
                let units = Array(String(ch).utf16)
                var glyphs = [CGGlyph](repeating: 0, count: units.count)
                XCTAssertTrue(CTFontGetGlyphsForCharacters(font, units, &glyphs, units.count), "\(r.style.name) has no glyph for \(ch)")
                XCTAssertNotEqual(glyphs[0], 0)
            }
            XCTAssertEqual(CTFontGetUnitsPerEm(font), 1000)
            XCTAssertEqual(CTFontGetAscent(font), 80, accuracy: 0.5)
            XCTAssertEqual(CTFontGetDescent(font), 20, accuracy: 0.5)

            // A glyph with an outline must produce a real path.
            var glyph = CGGlyph()
            var unit = UniChar(UnicodeScalar("A").value)
            CTFontGetGlyphsForCharacters(font, &unit, &glyph, 1)
            let path = try XCTUnwrap(CTFontCreatePathForGlyph(font, glyph, nil), r.style.name)
            XCTAssertGreaterThan(path.boundingBoxOfPath.width, 20)
            XCTAssertGreaterThan(path.boundingBoxOfPath.height, 40)
        }
    }

    func testDifferentFontsDrawDifferentShapes() throws {
        var seen: [String: String] = [:]
        for r in results {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(r.style.fileName)")
            try r.data.write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }
            let d = try XCTUnwrap(CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor])
            let font = CTFontCreateWithFontDescriptor(d[0], 100, nil)
            var unit = UniChar(UnicodeScalar("R").value)
            var glyph = CGGlyph()
            CTFontGetGlyphsForCharacters(font, &unit, &glyph, 1)
            let box = CTFontCreatePathForGlyph(font, glyph, nil)!.boundingBoxOfPath
            let signature = String(format: "%.1f,%.1f,%.1f,%.1f,%.1f", box.minX, box.minY, box.width, box.height, CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, nil, 1))
            if let other = seen[signature] { XCTFail("\(r.style.name) draws R exactly like \(other)") }
            seen[signature] = r.style.name
        }
    }
}

final class GeometryTests: XCTestCase {
    func testQuadIsClockwiseAndSizedByHalfWidth() throws {
        let q = try XCTUnwrap(Geo.quad(Pt(0, 0), Pt(100, 0), hw: 10))
        XCTAssertLessThan(Geo.area(q), 0)
        XCTAssertEqual(abs(Geo.area(q)), 100 * 20, accuracy: 1e-6)
    }

    func testFilletChamfersWithOneStepAndRoundsWithMany() {
        let corner = [Pt(0, 100), Pt(0, 0), Pt(100, 0)]
        let chamfer = Geo.fillet(corner, factors: [1, 1, 1], closed: false, radius: 30, steps: 1)
        XCTAssertEqual(chamfer.count, 4, "ends plus two chamfer points")
        let round = Geo.fillet(corner, factors: [1, 1, 1], closed: false, radius: 30, steps: 8)
        XCTAssertGreaterThan(round.count, 8)
        // Every arc point sits 30 units from the arc center, which is at (30, 30).
        for p in round.dropFirst().dropLast() { XCTAssertEqual(((p.x - 30) * (p.x - 30) + (p.y - 30) * (p.y - 30)).squareRoot(), 30, accuracy: 0.01) }
    }

    func testSharpCornersAndAcuteCornersStayPut() {
        let corner = [Pt(0, 100), Pt(0, 0), Pt(100, 0)]
        XCTAssertEqual(Geo.fillet(corner, factors: [1, 0, 1], closed: false, radius: 30, steps: 4).count, 3, "k = 0 keeps it sharp")
        let acute = [Pt(0, 0), Pt(50, 100), Pt(100, 0)]
        XCTAssertEqual(Geo.fillet(acute, factors: [1, 1, 1], closed: false, radius: 30, steps: 4).count, 3, "acute apex stays sharp")
    }

    func testJoinWedgeFillsTheOutsideOfABend() throws {
        let w = try XCTUnwrap(Geo.joinWedge(prev: Pt(0, 0), cur: Pt(100, 0), next: Pt(100, 100), hw: 10, miterLimit: 4))
        XCTAssertLessThan(Geo.area(w), 0)
        XCTAssertTrue(w.contains { abs($0.x - 110) < 0.01 && abs($0.y + 10) < 0.01 }, "the miter point is on the outside corner")
        XCTAssertNil(Geo.joinWedge(prev: Pt(0, 0), cur: Pt(50, 0), next: Pt(100, 0), hw: 10, miterLimit: 4), "no wedge on a straight line")
    }

    func testClipperRemovesTheCutPartOfASegment() {
        let pieces = Clipper.cut([Pt(0, 0), Pt(100, 0)], closed: false, rects: [(minX: 40, minY: -5, maxX: 60, maxY: 5)])
        XCTAssertEqual(pieces.count, 2)
        XCTAssertEqual(pieces[0].last?.x ?? 0, 40, accuracy: 1e-6)
        XCTAssertEqual(pieces[1].first?.x ?? 0, 60, accuracy: 1e-6)
    }

    func testHashIsDeterministicAndSpread() {
        XCTAssertEqual(hash01(3, 4, 5), hash01(3, 4, 5))
        let values = Set((0..<50).map { hash01($0, 7) })
        XCTAssertGreaterThan(values.count, 40)
        XCTAssertTrue(values.allSatisfy { (0..<1).contains($0) })
    }
}

final class WriterTests: XCTestCase {
    func testMinimalFontRoundTripsThroughTheReader() {
        let square = GlyphData(contours: [Geo.clockwise([Pt(0, 0), Pt(0, 500), Pt(500, 500), Pt(500, 0)])], advance: 600)
        let meta = FontMetadata(family: "Test", postScriptName: "Test-Regular", copyright: "c", license: "l", licenseURL: "u", designer: "d")
        let out = TTFWriter.write(meta: meta, notdef: square, glyphs: [65: square, 66: GlyphData(contours: [], advance: 300)])
        let f = SFNT(out.data)
        XCTAssertEqual(f.glyphCount, 3)
        XCTAssertEqual(f.glyphID(for: 65), 1)
        XCTAssertEqual(f.glyphID(for: 66), 2)
        XCTAssertEqual(f.glyph(1)?.header.maxX, 500)
        XCTAssertNil(f.glyph(2), "an empty glyph has no data")
        XCTAssertEqual(checksum(f.data[...]), 0xB1B0AFBA)
    }

    func testLargeAndSmallCoordinateDeltasSurviveTheCompactEncoding() {
        // Deltas of 0, under 256 and over 255 each take a different encoding path.
        let c: Contour = [Pt(0, 0), Pt(0, 900), Pt(30, 900), Pt(30, 0), Pt(-100, 0), Pt(-100, 1), Pt(700, -50)]
        let g = GlyphData(contours: [c], advance: 800)
        let meta = FontMetadata(family: "T", postScriptName: "T-Regular", copyright: "c", license: "l", licenseURL: "u", designer: "d")
        let f = SFNT(TTFWriter.write(meta: meta, notdef: g, glyphs: [65: g]).data)
        let decoded = f.glyph(1)!.contours[0].map { [$0.x, $0.y] }
        XCTAssertEqual(decoded, c.map { [Int($0.x), Int($0.y)] })
    }

    func testCmapSplitsNonConsecutiveRuns() {
        let g = GlyphData(contours: [[Pt(0, 0), Pt(0, 10), Pt(10, 10), Pt(10, 0)]], advance: 100)
        let meta = FontMetadata(family: "T", postScriptName: "T-Regular", copyright: "c", license: "l", licenseURL: "u", designer: "d")
        let f = SFNT(TTFWriter.write(meta: meta, notdef: g, glyphs: [65: g, 66: g, 200: g, 0x2014: g]).data)
        XCTAssertEqual([f.glyphID(for: 65), f.glyphID(for: 66), f.glyphID(for: 200), f.glyphID(for: 0x2014)], [1, 2, 3, 4])
        XCTAssertEqual(f.glyphID(for: 67), 0)
    }
}
