import Foundation
import CoreGraphics

public enum ScreenCorner: String, Codable, CaseIterable, Sendable {
    case topLeft, topRight, bottomLeft, bottomRight

    public var title: String {
        switch self {
        case .topLeft: return "Top Left"
        case .topRight: return "Top Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        }
    }
}

/// Corner mode: the lyrics in a small card in one corner of the screen instead of across the whole
/// display. It always uses the compact Karaoke Line style and has no edge lights.
public struct CornerOverlaySettings: Equatable, Codable, Sendable {
    public var enabled = false
    public var corner = ScreenCorner.bottomRight
    /// Text size of the current line, in points.
    public var fontSize = 22.0
    /// Card width in points.
    public var width = 420.0
    /// Gap between the card and the screen edge, in points.
    public var margin = 20.0
    public var showNextLine = false
    /// A translucent rounded panel behind the text so it stays readable on any window.
    public var showBackdrop = true
    /// High enough that white text stays readable even over a white window.
    public var backdropOpacity = 0.74

    public init() {}

    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = c.get(.enabled, enabled)
        corner = c.get(.corner, corner)
        fontSize = c.get(.fontSize, fontSize)
        width = c.get(.width, width)
        margin = c.get(.margin, margin)
        showNextLine = c.get(.showNextLine, showNextLine)
        showBackdrop = c.get(.showBackdrop, showBackdrop)
        backdropOpacity = c.get(.backdropOpacity, backdropOpacity)
    }
}

/// Where the corner card goes and how big it is. Pure, so it can be tested without a screen.
public enum CornerOverlay {
    /// Inner padding between the card edge and the text, in points.
    public static let padding = 14.0
    /// Sizes outside these are clamped, so a hand-edited settings file can't produce a useless card.
    public static let fontSizeRange = 12.0...48.0
    public static let widthRange = 220.0...900.0
    public static let marginRange = 0.0...120.0

    public static func clampedFontSize(_ s: CornerOverlaySettings) -> Double {
        min(fontSizeRange.upperBound, max(fontSizeRange.lowerBound, s.fontSize))
    }

    /// Card height in font sizes: two wrapped rows of the current line (each about 1.5 em with line
    /// spacing), with room above and below, plus a preview line when it is shown.
    static let rowsWithoutNext = 3.7
    static let rowsWithNext = 5.4

    /// Card size. Height holds two wrapped rows of the current line, plus the next line when shown,
    /// so the card is a stable size that doesn't jump as lines change.
    public static func size(for s: CornerOverlaySettings) -> CGSize {
        let font = clampedFontSize(s)
        let rows = s.showNextLine ? rowsWithNext : rowsWithoutNext
        let width = min(widthRange.upperBound, max(widthRange.lowerBound, s.width))
        return CGSize(width: width, height: (font * rows + padding * 2).rounded())
    }

    /// The card's frame in AppKit coordinates (origin bottom-left) inside `visibleFrame`, the screen
    /// area clear of the menu bar and Dock. A card too big for the area is shrunk to fit.
    public static func frame(in visibleFrame: CGRect, settings s: CornerOverlaySettings) -> CGRect {
        var size = self.size(for: s)
        let margin = min(marginRange.upperBound, max(marginRange.lowerBound, s.margin))
        size.width = min(size.width, max(1, visibleFrame.width - 2 * margin))
        size.height = min(size.height, max(1, visibleFrame.height - 2 * margin))

        let x: CGFloat
        switch s.corner {
        case .topLeft, .bottomLeft: x = visibleFrame.minX + margin
        case .topRight, .bottomRight: x = visibleFrame.maxX - margin - size.width
        }
        let y: CGFloat
        switch s.corner {
        case .bottomLeft, .bottomRight: y = visibleFrame.minY + margin
        case .topLeft, .topRight: y = visibleFrame.maxY - margin - size.height
        }
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// The overlay settings to lay lyrics out in the card: compact, centered, no heavy effects.
    public static func config(from base: OverlayConfig, settings s: CornerOverlaySettings) -> OverlayConfig {
        var c = base
        c.font = base.font.withSize(clampedFontSize(s))
        c.showNextLine = s.showNextLine
        c.maxWidthFraction = 0.94
        // The current line sits in the middle, higher when a preview line shares the card.
        c.anchorY = s.showNextLine ? 0.63 : 0.5
        c.glow = min(base.glow, 0.35)   // a big glow would spill past a small card
        // Small text on a translucent card needs more contrast than big text on a screen: brighter
        // unsung words, and a preview line that is big and bright enough to read.
        c.baseColor = base.baseColor.withAlpha(max(base.baseColor.a, 0.62))
        c.secondaryScale = max(base.secondaryScale, 0.72)
        c.secondaryOpacity = max(base.secondaryOpacity, 0.72)
        return c
    }

    /// The backdrop panel for a card of `size`: the whole card, drawn as a rounded rectangle.
    public static func backdrop(for s: CornerOverlaySettings, size: CGSize) -> PanelParams? {
        guard s.showBackdrop, s.backdropOpacity > 0.001 else { return nil }
        let opacity = Float(min(1, max(0, s.backdropOpacity)))
        return PanelParams(rect: CGRect(origin: .zero, size: size), cornerRadius: min(16, Double(min(size.width, size.height)) / 4),
                           color: RGBA(0.04, 0.04, 0.07, opacity))
    }
}

/// A rounded rectangle for the renderer to fill, in view points with the origin top-left.
public struct PanelParams: Equatable, Sendable {
    public var rect: CGRect
    public var cornerRadius: Double
    public var color: RGBA

    public init(rect: CGRect, cornerRadius: Double, color: RGBA) {
        self.rect = rect
        self.cornerRadius = cornerRadius
        self.color = color
    }
}
