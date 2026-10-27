import Foundation
import CoreGraphics

/// Finds an artwork's main colors with k-means in CIELAB, where distance matches what
/// people see. Fully deterministic: the same pixels always give the same palette.
public enum PaletteExtractor {
    typealias Lab = ColorMath.Lab

    /// Clusters smaller than this share of the image can't be the accent (stray pixels, JPEG noise).
    static let minimumAccentShare = 0.02
    /// Below this chroma a color counts as gray and loses to any real color for the accent.
    static let minimumAccentChroma = 15.0
    /// How different (Lab distance) the secondary must be from the dominant and the accent.
    static let distinctDeltaE = 25.0
    static let iterations = 8
    static let maxPoints = 16_384

    /// `pixels` is RGBA8, row-major. Alpha only decides whether a pixel is skipped
    /// (nearly transparent); color is taken as is. Returns nil if there is nothing to read.
    public static func extract(pixels: [UInt8], width: Int, height: Int, k: Int = 5) -> Palette? {
        guard width > 0, height > 0, k > 0, pixels.count >= width * height * 4 else { return nil }

        let total = width * height
        let step = max(1, total / maxPoints)
        var points: [Lab] = []
        var lumaSum = 0.0
        var index = 0
        while index < total {
            let o = index * 4
            if pixels[o + 3] >= 16 {
                let r = Double(pixels[o]) / 255, g = Double(pixels[o + 1]) / 255, b = Double(pixels[o + 2]) / 255
                points.append(ColorMath.lab(r: r, g: g, b: b))
                lumaSum += 0.2126 * r + 0.7152 * g + 0.0722 * b
            }
            index += step
        }
        guard !points.isEmpty else { return nil }

        let clusters = kMeans(points, k: k)
        guard !clusters.isEmpty else { return nil }
        return palette(from: clusters, meanLuma: lumaSum / Double(points.count))
    }

    /// Downsamples to about 64x64 first: plenty for color, and fast.
    public static func extract(from image: CGImage, k: Int = 5) -> Palette? {
        let size = 64
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let drew: Bool = pixels.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(
                data: buf.baseAddress, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
            return true
        }
        guard drew else { return nil }
        return extract(pixels: pixels, width: size, height: size, k: k)
    }

    // MARK: - K-means

    struct Cluster {
        var center: Lab
        var share: Double
    }

    /// Farthest-point initialization from the mean (no randomness), then a fixed number of
    /// Lloyd iterations. Empty clusters are dropped from the result.
    static func kMeans(_ points: [Lab], k: Int) -> [Cluster] {
        var mean = Lab(repeating: 0)
        for p in points { mean += p }
        mean /= Double(points.count)

        // First center: the point farthest from the mean; then repeatedly the point farthest
        // from every center so far. Stop early when all remaining points are already covered.
        var centers: [Lab] = []
        var minDist = points.map { ColorMath.deltaE($0, mean) }
        for _ in 0..<min(k, points.count) {
            var best = 0
            for i in 1..<points.count where minDist[i] > minDist[best] { best = i }
            if !centers.isEmpty, minDist[best] < 1e-6 { break }
            centers.append(points[best])
            for i in 0..<points.count { minDist[i] = min(minDist[i], ColorMath.deltaE(points[i], points[best])) }
            if centers.count == 1 { minDist = points.map { ColorMath.deltaE($0, points[best]) } }
        }

        var assignment = [Int](repeating: 0, count: points.count)
        for _ in 0..<iterations {
            for (i, p) in points.enumerated() {
                var best = 0
                var bestDist = Double.infinity
                for (c, center) in centers.enumerated() {
                    let d = ColorMath.deltaE(p, center)
                    if d < bestDist { bestDist = d; best = c }
                }
                assignment[i] = best
            }
            var sums = [Lab](repeating: Lab(repeating: 0), count: centers.count)
            var counts = [Int](repeating: 0, count: centers.count)
            for (i, p) in points.enumerated() { sums[assignment[i]] += p; counts[assignment[i]] += 1 }
            for c in 0..<centers.count where counts[c] > 0 { centers[c] = sums[c] / Double(counts[c]) }
        }

        var counts = [Int](repeating: 0, count: centers.count)
        for a in assignment { counts[a] += 1 }
        return centers.enumerated().compactMap { c, center in
            counts[c] > 0 ? Cluster(center: center, share: Double(counts[c]) / Double(points.count)) : nil
        }
    }

    // MARK: - Choosing colors

    static func palette(from clusters: [Cluster], meanLuma: Double) -> Palette {
        // Most common first; equal shares keep their original order (stable sort).
        let byShare = clusters.enumerated().sorted { a, b in
            a.element.share != b.element.share ? a.element.share > b.element.share : a.offset < b.offset
        }.map(\.element)

        let dominant = byShare[0]
        let accent = pickAccent(byShare)
        let secondary = pickSecondary(byShare, dominant: dominant, accent: accent)

        return Palette(
            dominant: ColorMath.rgba(from: dominant.center),
            accent: ColorMath.rgba(from: accent.center),
            secondary: ColorMath.rgba(from: secondary),
            swatches: byShare.map { ColorMath.rgba(from: $0.center) },
            isDark: meanLuma < 0.5)
    }

    /// The most vivid color that covers a real part of the image; for near-gray art, the brightest.
    private static func pickAccent(_ clusters: [Cluster]) -> Cluster {
        let significant = clusters.filter { $0.share >= minimumAccentShare }
        let pool = significant.isEmpty ? clusters : significant

        let vivid = pool.filter { ColorMath.chroma($0.center) >= minimumAccentChroma }
        if let best = vivid.max(by: { score($0) < score($1) }) { return best }
        return pool.max(by: { $0.center.x < $1.center.x }) ?? clusters[0]
    }

    private static func score(_ c: Cluster) -> Double {
        ColorMath.chroma(c.center) * c.share.squareRoot()
    }

    /// The most common color clearly different from both; else the most distant leftover;
    /// else the dominant color shifted lighter or darker so there is always some contrast.
    private static func pickSecondary(_ clusters: [Cluster], dominant: Cluster, accent: Cluster) -> Lab {
        func isSame(_ a: Cluster, _ b: Cluster) -> Bool { a.center == b.center }
        let others = clusters.filter { !isSame($0, dominant) && !isSame($0, accent) }

        if let distinct = others.first(where: {
            ColorMath.deltaE($0.center, dominant.center) > distinctDeltaE && ColorMath.deltaE($0.center, accent.center) > distinctDeltaE
        }) {
            return distinct.center
        }
        if let farthest = others.max(by: { separation($0, dominant, accent) < separation($1, dominant, accent) }) {
            return farthest.center
        }
        if !isSame(accent, dominant) { return accent.center }

        var shifted = dominant.center
        shifted.x += shifted.x < 50 ? 28 : -28
        return shifted
    }

    private static func separation(_ c: Cluster, _ a: Cluster, _ b: Cluster) -> Double {
        min(ColorMath.deltaE(c.center, a.center), ColorMath.deltaE(c.center, b.center))
    }
}
