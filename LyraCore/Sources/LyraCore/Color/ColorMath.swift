import Foundation

/// sRGB <-> CIELAB (D65) conversions. Lab is stored as SIMD3 (x = L, y = a, z = b).
enum ColorMath {
    typealias Lab = SIMD3<Double>

    private static let white = SIMD3<Double>(0.95047, 1.0, 1.08883)
    private static let epsilon = 0.008856
    private static let eps16 = 16.0 / 116.0

    static func lab(from c: RGBA) -> Lab {
        lab(r: Double(c.r), g: Double(c.g), b: Double(c.b))
    }

    /// Components are 0...1, gamma-encoded sRGB.
    static func lab(r: Double, g: Double, b: Double) -> Lab {
        let lr = linear(r), lg = linear(g), lb = linear(b)
        let x = 0.4124564 * lr + 0.3575761 * lg + 0.1804375 * lb
        let y = 0.2126729 * lr + 0.7151522 * lg + 0.0721750 * lb
        let z = 0.0193339 * lr + 0.1191920 * lg + 0.9503041 * lb
        let fx = f(x / white.x), fy = f(y / white.y), fz = f(z / white.z)
        return Lab(116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    }

    /// Converts back to sRGB. Colors outside the sRGB gamut keep their lightness and hue and
    /// lose chroma until they fit, which looks far better than clipping channels.
    static func rgba(from lab: Lab, alpha: Float = 1) -> RGBA {
        var scale = 1.0
        if !inGamut(lab) {
            var lo = 0.0, hi = 1.0
            for _ in 0..<24 {
                let mid = (lo + hi) / 2
                if inGamut(Lab(lab.x, lab.y * mid, lab.z * mid)) { lo = mid } else { hi = mid }
            }
            scale = lo
        }
        let (r, g, b) = srgb(Lab(lab.x, lab.y * scale, lab.z * scale))
        return RGBA(Float(clamp01(r)), Float(clamp01(g)), Float(clamp01(b)), alpha)
    }

    /// Raises lightness to at least `minL`, keeping hue and as much chroma as fits.
    static func lifted(_ c: RGBA, minL: Double) -> RGBA {
        var l = lab(from: c)
        guard l.x < minL else { return c }
        l.x = minL
        return rgba(from: l, alpha: c.a)
    }

    static func deltaE(_ a: Lab, _ b: Lab) -> Double {
        let d = a - b
        return (d * d).sum().squareRoot()
    }

    static func chroma(_ l: Lab) -> Double { (l.y * l.y + l.z * l.z).squareRoot() }

    /// Gamma-encoded luma, 0...1.
    static func luma(_ c: RGBA) -> Double {
        0.2126 * Double(c.r) + 0.7152 * Double(c.g) + 0.0722 * Double(c.b)
    }

    // MARK: - Internals

    private static func linear(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    private static func gamma(_ c: Double) -> Double {
        c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055
    }

    private static func f(_ t: Double) -> Double {
        t > epsilon ? cbrt(t) : 7.787 * t + eps16
    }

    private static func finv(_ t: Double) -> Double {
        let t3 = t * t * t
        return t3 > epsilon ? t3 : (t - eps16) / 7.787
    }

    private static func srgb(_ lab: Lab) -> (Double, Double, Double) {
        let fy = (lab.x + 16) / 116
        let fx = fy + lab.y / 500
        let fz = fy - lab.z / 200
        let x = finv(fx) * white.x, y = finv(fy) * white.y, z = finv(fz) * white.z
        let r = 3.2404542 * x - 1.5371385 * y - 0.4985314 * z
        let g = -0.9692660 * x + 1.8760108 * y + 0.0415560 * z
        let b = 0.0556434 * x - 0.2040259 * y + 1.0572252 * z
        return (gamma(max(0, r)), gamma(max(0, g)), gamma(max(0, b)))
    }

    private static func inGamut(_ lab: Lab) -> Bool {
        let fy = (lab.x + 16) / 116
        let fx = fy + lab.y / 500
        let fz = fy - lab.z / 200
        let x = finv(fx) * white.x, y = finv(fy) * white.y, z = finv(fz) * white.z
        let r = 3.2404542 * x - 1.5371385 * y - 0.4985314 * z
        let g = -0.9692660 * x + 1.8760108 * y + 0.0415560 * z
        let b = 0.0556434 * x - 0.2040259 * y + 1.0572252 * z
        let tol = 0.0005
        return [r, g, b].allSatisfy { $0 >= -tol && $0 <= 1 + tol }
    }

    private static func clamp01(_ v: Double) -> Double { min(1, max(0, v)) }
}
