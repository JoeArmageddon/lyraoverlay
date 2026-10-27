import Foundation

public enum BackgroundKind: String, Codable, CaseIterable, Sendable {
    case image
    case video
    /// A generated gradient described by `BackgroundItem.stops`; no file involved.
    case gradient
}

/// One choice for the player window's background: a built-in gradient or a file the user added.
public struct BackgroundItem: Identifiable, Codable, Equatable, Sendable {
    /// Built-ins start with "builtin."; user items with "user.".
    public var id: String
    public var name: String
    public var kind: BackgroundKind
    /// File name inside the library's `Files` folder; nil for gradients.
    public var fileName: String?
    /// Gradient colors from top-left to bottom-right; empty for images and videos.
    public var stops: [RGBA]
    public var addedAt: Date
    /// Colors of the background, computed once so the border can use them without decoding.
    public var palette: Palette?

    public var isBuiltIn: Bool { id.hasPrefix("builtin.") }

    public init(id: String, name: String, kind: BackgroundKind, fileName: String? = nil, stops: [RGBA] = [],
                addedAt: Date = Date(timeIntervalSince1970: 0), palette: Palette? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.fileName = fileName
        self.stops = stops
        self.addedAt = addedAt
        self.palette = palette
    }

    /// Tolerant: identity is required, everything else falls back, so one odd entry in the
    /// index never takes the whole library down.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = c.get(.name, id)
        kind = c.get(.kind, .image)
        fileName = (try? c.decodeIfPresent(String.self, forKey: .fileName)) ?? nil
        stops = c.get(.stops, [])
        addedAt = c.get(.addedAt, Date(timeIntervalSince1970: 0))
        palette = (try? c.decodeIfPresent(Palette.self, forKey: .palette)) ?? nil
    }

    /// The palette of a gradient, found by running the normal extractor over a rendering of it,
    /// so built-ins and uploads are colored by exactly the same code.
    public static func gradientPalette(_ stops: [RGBA]) -> Palette? {
        guard !stops.isEmpty else { return nil }
        let n = 48
        var pixels = [UInt8](repeating: 255, count: n * n * 4)
        for y in 0..<n {
            for x in 0..<n {
                let t = Double(x + y) / Double(2 * (n - 1))
                let c = color(at: t, in: stops)
                let i = (y * n + x) * 4
                pixels[i] = UInt8((c.r * 255).rounded())
                pixels[i + 1] = UInt8((c.g * 255).rounded())
                pixels[i + 2] = UInt8((c.b * 255).rounded())
            }
        }
        return PaletteExtractor.extract(pixels: pixels, width: n, height: n)
    }

    /// Piecewise-linear color along the stops for `t` in 0...1.
    static func color(at t: Double, in stops: [RGBA]) -> RGBA {
        guard stops.count > 1 else { return stops.first ?? .white }
        let scaled = min(max(t, 0), 1) * Double(stops.count - 1)
        let i = min(Int(scaled), stops.count - 2)
        let f = Float(scaled - Double(i))
        let a = stops[i], b = stops[i + 1]
        return RGBA(a.r + (b.r - a.r) * f, a.g + (b.g - a.g) * f, a.b + (b.b - a.b) * f, 1)
    }
}
