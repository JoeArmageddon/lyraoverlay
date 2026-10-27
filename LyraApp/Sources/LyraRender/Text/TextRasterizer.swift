import AppKit
import CoreText
import LyraCore

/// White text on a transparent background, premultiplied BGRA, ready to upload as a texture.
/// The renderer tints it, so one texture serves every color.
struct RasterizedText {
    var pixels: [UInt8]
    var pixelWidth: Int
    var pixelHeight: Int
    /// Text bounds inside the bitmap as 0...1 horizontal fractions, for the sung wipe.
    var textStartU: Float
    var textEndU: Float
}

enum TextRasterizer {
    /// Padding around the text, in em, so glow and shadow can spread past the glyphs.
    static let paddingEm = 0.4

    static func rasterize(_ text: String, font: FontSpec, scale: CGFloat) -> RasterizedText? {
        // The same layout the measurer uses, so drawn width equals measured width (tracking included).
        let layout = TextLayout(text, font, foreground: .white)
        let line = layout.line
        let width = layout.width, ascent = layout.ascent, descent = layout.descent
        guard width > 0 else { return nil }

        let pad = CGFloat(font.size * paddingEm)
        let widthPt = width + 2 * pad
        let heightPt = ascent + descent + 2 * pad
        let pw = max(1, Int((widthPt * scale).rounded(.up)))
        let ph = max(1, Int((heightPt * scale).rounded(.up)))

        var pixels = [UInt8](repeating: 0, count: pw * ph * 4)
        let drew: Bool = pixels.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(
                data: buf.baseAddress, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: pw * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return false }
            ctx.scaleBy(x: scale, y: scale)
            // Grayscale antialiasing only: LCD smoothing would fringe on a transparent background.
            ctx.setShouldAntialias(true)
            ctx.setShouldSmoothFonts(false)
            ctx.setShouldSubpixelPositionFonts(true)
            ctx.textPosition = CGPoint(x: pad, y: pad + descent)
            CTLineDraw(line, ctx)
            return true
        }
        guard drew else { return nil }

        // Text spans pad...pad+width of the padded bitmap.
        return RasterizedText(
            pixels: pixels, pixelWidth: pw, pixelHeight: ph,
            textStartU: Float(pad / widthPt), textEndU: Float((pad + width) / widthPt))
    }
}
