import Foundation

/// One glyph ready to be written: outlines in font units (clockwise outers), plus its advance.
public struct GlyphData {
    public var contours: [[Pt]]
    public var advance: Int
    public init(contours: [[Pt]], advance: Int) { self.contours = contours; self.advance = advance }
}

public struct FontMetadata {
    public var family: String
    public var postScriptName: String
    public var copyright: String
    public var license: String
    public var licenseURL: String
    public var designer: String
    public var weightClass: Int
    public var isMonospaced: Bool
    /// Slant of the italic angle in degrees, negative for a lean to the right.
    public var italicAngle: Double
    public var xHeight: Int
    public var capHeight: Int
    public var unitsPerEm = 1000
    public var ascender = 800
    public var descender = -200

    public init(family: String, postScriptName: String, copyright: String, license: String, licenseURL: String,
                designer: String, weightClass: Int = 400, isMonospaced: Bool = false, italicAngle: Double = 0,
                xHeight: Int = 500, capHeight: Int = 700) {
        self.family = family; self.postScriptName = postScriptName; self.copyright = copyright
        self.license = license; self.licenseURL = licenseURL; self.designer = designer
        self.weightClass = weightClass; self.isMonospaced = isMonospaced; self.italicAngle = italicAngle
        self.xHeight = xHeight; self.capHeight = capHeight
    }
}

/// Writes a TrueType-outline font (sfnt 1.0) from glyph outlines. Glyph order is by the sorted
/// Unicode scalar, with `.notdef` first and then each mapped scalar; unmapped glyphs are not used.
public enum TTFWriter {
    public struct Output {
        public var data: Data
        public var glyphCount: Int
    }

    // MARK: - Binary helpers

    struct Buffer {
        var bytes: [UInt8] = []
        mutating func u8(_ v: Int) { bytes.append(UInt8(truncatingIfNeeded: v)) }
        mutating func u16(_ v: Int) { bytes.append(UInt8(truncatingIfNeeded: v >> 8)); bytes.append(UInt8(truncatingIfNeeded: v)) }
        mutating func i16(_ v: Int) { u16(Int(Int16(truncatingIfNeeded: v)) & 0xFFFF) }
        mutating func u32(_ v: UInt32) { for s in [24, 16, 8, 0] { bytes.append(UInt8(truncatingIfNeeded: v >> UInt32(s))) } }
        mutating func i64(_ v: Int64) { for s in stride(from: 56, through: 0, by: -8) { bytes.append(UInt8(truncatingIfNeeded: v >> Int64(s))) } }
        mutating func fixed(_ v: Double) { u32(UInt32(bitPattern: Int32((v * 65536).rounded()))) }
        mutating func tag(_ s: String) { bytes.append(contentsOf: Array(s.utf8.prefix(4))) }
        mutating func pad4() { while bytes.count % 4 != 0 { bytes.append(0) } }
    }

    static func checksum(_ bytes: [UInt8]) -> UInt32 {
        var sum: UInt32 = 0
        var i = 0
        while i < bytes.count {
            var word: UInt32 = 0
            for k in 0..<4 { word = (word << 8) | UInt32(i + k < bytes.count ? bytes[i + k] : 0) }
            sum = sum &+ word
            i += 4
        }
        return sum
    }

    // MARK: - Public entry

    /// `glyphs` maps a Unicode scalar to its glyph; `notdef` is glyph 0.
    public static func write(meta: FontMetadata, notdef: GlyphData, glyphs: [UInt32: GlyphData]) -> Output {
        let codes = glyphs.keys.sorted().filter { $0 <= 0xFFFF }
        var ordered: [GlyphData] = [notdef]
        ordered.append(contentsOf: codes.map { glyphs[$0]! })

        // Round every outline to integers once, so the bounding boxes written to the file match exactly.
        let rounded: [[[(x: Int, y: Int)]]] = ordered.map { g in
            g.contours.map { c in c.map { (x: Int($0.x.rounded()), y: Int($0.y.rounded())) } }
        }

        var glyf = Buffer()
        var loca: [UInt32] = []
        var boxes: [(minX: Int, minY: Int, maxX: Int, maxY: Int)] = []
        var maxPoints = 0, maxContours = 0
        for contours in rounded {
            loca.append(UInt32(glyf.bytes.count))
            let all = contours.flatMap { $0 }
            if all.isEmpty { boxes.append((0, 0, 0, 0)); continue }
            let box = (minX: all.map(\.x).min()!, minY: all.map(\.y).min()!, maxX: all.map(\.x).max()!, maxY: all.map(\.y).max()!)
            boxes.append(box)
            maxPoints = max(maxPoints, all.count)
            maxContours = max(maxContours, contours.count)
            encodeGlyph(contours, box: box, into: &glyf)
            glyf.pad4()
        }
        loca.append(UInt32(glyf.bytes.count))

        // Global metrics.
        let xMin = boxes.map(\.minX).min() ?? 0, yMin = boxes.map(\.minY).min() ?? 0
        let xMax = boxes.map(\.maxX).max() ?? 0, yMax = boxes.map(\.maxY).max() ?? 0
        let advances = ordered.map(\.advance)
        let advanceMax = advances.max() ?? 0
        var minLSB = Int.max, minRSB = Int.max, maxExtent = 0
        for (i, g) in ordered.enumerated() where !rounded[i].isEmpty {
            let b = boxes[i]
            minLSB = min(minLSB, b.minX)
            minRSB = min(minRSB, g.advance - b.maxX)
            maxExtent = max(maxExtent, b.maxX)
        }
        if minLSB == Int.max { minLSB = 0; minRSB = 0 }

        // Tables.
        var tables: [(tag: String, data: [UInt8])] = []

        // head (checkSumAdjustment is patched in after the whole file is laid out)
        var head = Buffer()
        head.fixed(1.0); head.fixed(1.0)
        head.u32(0)                       // checkSumAdjustment
        head.u32(0x5F0F3CF5)
        head.u16(0x000B)                  // y=0 baseline, lsb at xMin, integer ppem
        head.u16(meta.unitsPerEm)
        head.i64(3_786_825_600)           // created: 2024-01-01, seconds since 1904
        head.i64(3_786_825_600)
        head.i16(xMin); head.i16(yMin); head.i16(xMax); head.i16(yMax)
        head.u16(0)                       // macStyle
        head.u16(8)                       // lowestRecPPEM
        head.i16(2)                       // fontDirectionHint
        head.i16(1)                       // long loca
        head.i16(0)
        tables.append(("head", head.bytes))

        // hhea
        var hhea = Buffer()
        hhea.fixed(1.0)
        hhea.i16(meta.ascender); hhea.i16(meta.descender); hhea.i16(0)
        hhea.u16(advanceMax); hhea.i16(minLSB); hhea.i16(minRSB); hhea.i16(maxExtent)
        // The caret follows the italic angle so selections lean with the letters.
        let slope = tan(-meta.italicAngle * .pi / 180)
        hhea.i16(1000); hhea.i16(Int((slope * 1000).rounded())); hhea.i16(0)
        for _ in 0..<4 { hhea.i16(0) }
        hhea.i16(0)
        hhea.u16(ordered.count)
        tables.append(("hhea", hhea.bytes))

        // maxp
        var maxp = Buffer()
        maxp.fixed(1.0)
        maxp.u16(ordered.count); maxp.u16(maxPoints); maxp.u16(maxContours)
        maxp.u16(0); maxp.u16(0); maxp.u16(2); maxp.u16(0); maxp.u16(0); maxp.u16(0); maxp.u16(0)
        maxp.u16(0); maxp.u16(0); maxp.u16(0); maxp.u16(0)
        tables.append(("maxp", maxp.bytes))

        // hmtx
        var hmtx = Buffer()
        for (i, g) in ordered.enumerated() { hmtx.u16(g.advance); hmtx.i16(rounded[i].isEmpty ? 0 : boxes[i].minX) }
        tables.append(("hmtx", hmtx.bytes))

        // loca, glyf
        var locaBuf = Buffer()
        for o in loca { locaBuf.u32(o) }
        tables.append(("loca", locaBuf.bytes))
        tables.append(("glyf", glyf.bytes))

        tables.append(("cmap", cmapTable(codes: codes)))
        tables.append(("name", nameTable(meta)))
        tables.append(("post", postTable(meta)))
        tables.append(("OS/2", os2Table(meta, codes: codes, advances: advances, yMax: yMax, yMin: yMin)))

        tables.sort { $0.tag < $1.tag }
        return Output(data: assemble(tables), glyphCount: ordered.count)
    }

    // MARK: - glyf

    static func encodeGlyph(_ contours: [[(x: Int, y: Int)]], box: (minX: Int, minY: Int, maxX: Int, maxY: Int), into b: inout Buffer) {
        b.i16(contours.count)
        b.i16(box.minX); b.i16(box.minY); b.i16(box.maxX); b.i16(box.maxY)
        var end = -1
        for c in contours { end += c.count; b.u16(end) }
        b.u16(0)                          // no instructions

        let points = contours.flatMap { $0 }
        var flags: [UInt8] = [], xs: [UInt8] = [], ys: [UInt8] = []
        var px = 0, py = 0
        for (i, p) in points.enumerated() {
            var f: UInt8 = 0x01           // on curve
            if i == 0 { f |= 0x40 }       // OVERLAP_SIMPLE: contours overlap on purpose
            let dx = p.x - px, dy = p.y - py
            px = p.x; py = p.y
            if dx == 0 { f |= 0x10 } else if abs(dx) <= 255 { f |= 0x02; if dx > 0 { f |= 0x10 }; xs.append(UInt8(abs(dx))) }
            else { xs.append(UInt8(truncatingIfNeeded: dx >> 8)); xs.append(UInt8(truncatingIfNeeded: dx)) }
            if dy == 0 { f |= 0x20 } else if abs(dy) <= 255 { f |= 0x04; if dy > 0 { f |= 0x20 }; ys.append(UInt8(abs(dy))) }
            else { ys.append(UInt8(truncatingIfNeeded: dy >> 8)); ys.append(UInt8(truncatingIfNeeded: dy)) }
            flags.append(f)
        }
        b.bytes.append(contentsOf: flags)
        b.bytes.append(contentsOf: xs)
        b.bytes.append(contentsOf: ys)
    }

    // MARK: - cmap (format 4)

    static func cmapTable(codes: [UInt32]) -> [UInt8] {
        // Glyph ids are assigned in code order starting at 1, so each run of consecutive code points
        // maps to consecutive glyph ids and needs only an idDelta.
        struct Segment { var start: Int; var end: Int; var delta: Int }
        var segments: [Segment] = []
        for (index, code) in codes.enumerated() {
            let c = Int(code), gid = index + 1
            if var last = segments.last, last.end + 1 == c, last.delta == gid - c {
                last.end = c
                segments[segments.count - 1] = last
            } else {
                segments.append(Segment(start: c, end: c, delta: gid - c))
            }
        }
        segments.append(Segment(start: 0xFFFF, end: 0xFFFF, delta: 1))   // maps to glyph 0
        let segCount = segments.count
        var entrySelector = 0
        while (1 << (entrySelector + 1)) <= segCount { entrySelector += 1 }
        let searchRange = 2 * (1 << entrySelector)

        var sub = Buffer()
        sub.u16(4)
        sub.u16(16 + segCount * 8)
        sub.u16(0)
        sub.u16(segCount * 2); sub.u16(searchRange); sub.u16(entrySelector); sub.u16(segCount * 2 - searchRange)
        for s in segments { sub.u16(s.end) }
        sub.u16(0)
        for s in segments { sub.u16(s.start) }
        for s in segments { sub.i16(s.delta) }
        for _ in segments { sub.u16(0) }

        var t = Buffer()
        t.u16(0); t.u16(2)
        t.u16(0); t.u16(3); t.u32(20)     // Unicode BMP
        t.u16(3); t.u16(1); t.u32(20)     // Windows Unicode BMP
        t.bytes.append(contentsOf: sub.bytes)
        return t.bytes
    }

    // MARK: - name

    static func nameTable(_ m: FontMetadata) -> [UInt8] {
        let version = "Version 1.000"
        let records: [(id: Int, text: String)] = [
            (0, m.copyright), (1, m.family), (2, "Regular"),
            (3, "\(m.postScriptName);1.000"), (4, "\(m.family) Regular"), (5, version),
            (6, m.postScriptName), (9, m.designer), (13, m.license), (14, m.licenseURL),
        ]
        struct Rec { var platform: Int; var encoding: Int; var language: Int; var id: Int; var bytes: [UInt8] }
        var recs: [Rec] = []
        for r in records {
            recs.append(Rec(platform: 1, encoding: 0, language: 0, id: r.id, bytes: Array(r.text.utf8.map { $0 < 128 ? $0 : 63 })))
            var utf16: [UInt8] = []
            for u in r.text.utf16 { utf16.append(UInt8(u >> 8)); utf16.append(UInt8(u & 0xFF)) }
            recs.append(Rec(platform: 3, encoding: 1, language: 0x409, id: r.id, bytes: utf16))
        }
        recs.sort { ($0.platform, $0.encoding, $0.language, $0.id) < ($1.platform, $1.encoding, $1.language, $1.id) }

        var strings: [UInt8] = []
        var t = Buffer()
        t.u16(0); t.u16(recs.count); t.u16(6 + recs.count * 12)
        for r in recs {
            t.u16(r.platform); t.u16(r.encoding); t.u16(r.language); t.u16(r.id)
            t.u16(r.bytes.count); t.u16(strings.count)
            strings.append(contentsOf: r.bytes)
        }
        t.bytes.append(contentsOf: strings)
        return t.bytes
    }

    // MARK: - post

    static func postTable(_ m: FontMetadata) -> [UInt8] {
        var t = Buffer()
        t.u32(0x00030000)
        t.fixed(m.italicAngle)
        t.i16(-100); t.i16(50)
        t.u32(m.isMonospaced ? 1 : 0)
        t.u32(0); t.u32(0); t.u32(0); t.u32(0)
        return t.bytes
    }

    // MARK: - OS/2

    static func os2Table(_ m: FontMetadata, codes: [UInt32], advances: [Int], yMax: Int, yMin: Int) -> [UInt8] {
        var t = Buffer()
        let nonZero = advances.filter { $0 > 0 }
        t.u16(4)
        t.i16(nonZero.isEmpty ? 500 : nonZero.reduce(0, +) / nonZero.count)
        t.u16(m.weightClass); t.u16(5); t.u16(0)
        t.i16(650); t.i16(600); t.i16(0); t.i16(75)      // subscript
        t.i16(650); t.i16(600); t.i16(0); t.i16(350)     // superscript
        t.i16(50); t.i16(300)                            // strikeout
        t.i16(0)
        for _ in 0..<10 { t.u8(0) }                      // panose
        t.u32(0x00000003); t.u32(0); t.u32(0); t.u32(0)  // Basic Latin, Latin-1
        t.bytes.append(contentsOf: Array("LYRA".utf8))
        t.u16(m.italicAngle != 0 ? 0x0001 | 0x0040 | 0x0080 : 0x0040 | 0x0080)  // regular, use typo metrics
        t.u16(Int(codes.first ?? 32)); t.u16(Int(min(codes.last ?? 0x7E, 0xFFFF)))
        t.i16(m.ascender); t.i16(m.descender); t.i16(0)
        t.u16(max(yMax, 900)); t.u16(max(-yMin, 250))
        t.u32(0x00000001); t.u32(0)
        t.i16(m.xHeight); t.i16(m.capHeight)
        t.u16(0); t.u16(32); t.u16(1)
        return t.bytes
    }

    // MARK: - Assembly

    static func assemble(_ tables: [(tag: String, data: [UInt8])]) -> Data {
        let count = tables.count
        var entrySelector = 0
        while (1 << (entrySelector + 1)) <= count { entrySelector += 1 }
        let searchRange = 16 * (1 << entrySelector)

        var out = Buffer()
        out.u32(0x00010000)
        out.u16(count); out.u16(searchRange); out.u16(entrySelector); out.u16(count * 16 - searchRange)

        var offset = 12 + count * 16
        var placed: [(tag: String, offset: Int, bytes: [UInt8])] = []
        for t in tables {
            var padded = t.data
            while padded.count % 4 != 0 { padded.append(0) }
            placed.append((t.tag, offset, padded))
            out.tag(t.tag)
            out.u32(checksum(t.data))
            out.u32(UInt32(offset))
            out.u32(UInt32(t.data.count))
            offset += padded.count
        }
        for p in placed { out.bytes.append(contentsOf: p.bytes) }

        // checkSumAdjustment: the whole file must sum to 0xB1B0AFBA.
        let whole = checksum(out.bytes)
        let adjustment = 0xB1B0AFBA &- whole
        if let head = placed.first(where: { $0.tag == "head" }) {
            let at = head.offset + 8
            // The head table's directory checksum stays the one computed with this field zeroed.
            for (i, s) in [24, 16, 8, 0].enumerated() { out.bytes[at + i] = UInt8(truncatingIfNeeded: adjustment >> UInt32(s)) }
        }
        return Data(out.bytes)
    }
}
