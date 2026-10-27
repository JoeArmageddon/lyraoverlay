import AppKit
import CoreText
import LyraCore

public enum FontResolver {
    /// The system font for "System", otherwise a font looked up by PostScript or
    /// family name, falling back to the system font when it isn't installed.
    /// Italic uses a real italic face when the family has one, else a synthetic slant.
    public static func ctFont(_ spec: FontSpec) -> CTFont {
        let size = CGFloat(spec.size)
        var nsFont: NSFont
        // A custom font that was just removed counts as gone even while CoreText still remembers it.
        if spec.family.isEmpty || spec.family == "System" || FontCatalog.isRemoved(spec.family) {
            nsFont = .systemFont(ofSize: size, weight: NSFont.Weight(CGFloat(spec.weight)))
        } else if let named = NSFont(name: spec.family, size: size) {
            nsFont = named
        } else if let family = NSFontManager.shared.font(withFamily: spec.family, traits: [], weight: managerWeight(spec.weight), size: size) {
            nsFont = family
        } else {
            nsFont = .systemFont(ofSize: size, weight: NSFont.Weight(CGFloat(spec.weight)))
        }
        // NSFont and CTFont are toll-free bridged.
        var font = unsafeBitCast(nsFont, to: CTFont.self)
        if spec.italic { font = italicVersion(of: nsFont) ?? slanted(font) }
        return font
    }

    /// The family's real italic when it has one.
    private static func italicVersion(of font: NSFont) -> CTFont? {
        let manager = NSFontManager.shared
        if manager.traits(of: font).contains(.italicFontMask) { return unsafeBitCast(font, to: CTFont.self) }
        let converted = manager.convert(font, toHaveTrait: .italicFontMask)
        guard manager.traits(of: converted).contains(.italicFontMask) else { return nil }
        return unsafeBitCast(converted, to: CTFont.self)
    }

    /// Synthetic oblique (about 12 degrees) for families without an italic face.
    private static func slanted(_ font: CTFont) -> CTFont {
        var shear = CGAffineTransform(a: 1, b: 0, c: CGFloat(tan(12.0 * Double.pi / 180)), d: 1, tx: 0, ty: 0)
        return CTFontCreateCopyWithAttributes(font, CTFontGetSize(font), &shear, nil)
    }

    /// Maps NSFont.Weight (-1...1) to NSFontManager's 0...15 scale (5 regular, 9 bold).
    static func managerWeight(_ w: Double) -> Int {
        let table: [(Double, Int)] = [(-0.8, 1), (-0.6, 2), (-0.4, 3), (0, 5), (0.23, 6), (0.3, 8), (0.4, 9), (0.56, 10), (0.62, 12)]
        return table.min { abs($0.0 - w) < abs($1.0 - w) }?.1 ?? 5
    }
}

/// One line of text laid out by CoreText. Measuring and drawing both go through this,
/// so the width layout centers on is exactly the width that gets drawn.
struct TextLayout {
    let line: CTLine
    /// Glyph run width. CoreText adds tracking after the last character too; that trailing
    /// gap is excluded so centered text isn't pushed off-center by half the tracking.
    let width: CGFloat
    let ascent: CGFloat
    let descent: CGFloat
    let leading: CGFloat

    init(_ text: String, _ font: FontSpec, foreground: NSColor? = nil) {
        var attrs: [NSAttributedString.Key: Any] = [.font: FontResolver.ctFont(font)]
        let kern = CGFloat(font.tracking * font.size)
        if kern != 0 { attrs[.kern] = kern }
        if let foreground { attrs[.foregroundColor] = foreground }

        line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
        var a: CGFloat = 0, d: CGFloat = 0, l: CGFloat = 0
        let raw = CGFloat(CTLineGetTypographicBounds(line, &a, &d, &l))
        ascent = a; descent = d; leading = l
        width = text.isEmpty ? 0 : max(0, raw - kern)
    }
}

/// Real text measurement through CoreText, with a small cache since layout asks every frame.
public final class CoreTextMeasurer: TextMeasuring, @unchecked Sendable {
    private let lock = NSLock()
    private var widths: [String: CGFloat] = [:]

    public init() {}

    public func width(of text: String, font: FontSpec) -> CGFloat {
        let key = "\(font.family)|\(font.size)|\(font.weight)|\(font.tracking)|\(font.italic)|\(text)"
        if let cached = lock.withLock({ widths[key] }) { return cached }
        let w = TextLayout(text, font).width
        lock.withLock {
            if widths.count > 4000 { widths.removeAll() }
            widths[key] = w
        }
        return w
    }

    public func lineHeight(font: FontSpec) -> CGFloat {
        let layout = TextLayout("Hg", font)
        return layout.ascent + layout.descent + layout.leading
    }
}
