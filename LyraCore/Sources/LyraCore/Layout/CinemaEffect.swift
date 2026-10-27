import Foundation
import CoreGraphics

/// One frame of film-look finishing, in terms the renderer can draw. All positions are in view
/// points with the origin at the top left, like `DrawItem`.
public struct CinemaFrame: Equatable, Sendable {
    /// Height of each letterbox bar as a fraction of the view height (0 when there are no bars).
    public var barFraction: Double
    /// 0...1 darkening toward the corners of the picture.
    public var vignette: Float
    /// 0...1 film grain strength.
    public var grain: Float
    /// Changes about 24 times a second so the grain animates like film rather than shimmering.
    public var grainSeed: Float
    /// 0...1 current strength of the light streak.
    public var flare: Float
    public var flareCenter: CGPoint
    /// Half the streak's length in points.
    public var flareHalfWidth: Double

    public init(barFraction: Double, vignette: Float, grain: Float, grainSeed: Float, flare: Float,
                flareCenter: CGPoint, flareHalfWidth: Double) {
        self.barFraction = barFraction
        self.vignette = vignette
        self.grain = grain
        self.grainSeed = grainSeed
        self.flare = flare
        self.flareCenter = flareCenter
        self.flareHalfWidth = flareHalfWidth
    }

    /// The picture area inside the bars, for a view of `viewport` size.
    public func pictureRect(in viewport: CGSize) -> CGRect {
        let bar = CGFloat(barFraction) * viewport.height
        return CGRect(x: 0, y: bar, width: viewport.width, height: max(0, viewport.height - 2 * bar))
    }
}

public enum CinemaEffect {
    /// Grain frames per second: film runs at 24.
    public static let grainRate = 24.0
    /// The streak never goes fully dark, so the film look stays alive between beats.
    static let restingFlare: Float = 0.12

    /// The picture area: the largest rect of the letterbox aspect that fits centered in the view.
    /// A view already wider than the ratio gets no bars (never pillarboxed), and disabled cinema,
    /// no letterbox or an empty view all give the whole view.
    public static func pictureRect(settings: CinemaSettings, viewport: CGSize) -> CGRect {
        let full = CGRect(origin: .zero, size: viewport)
        guard settings.enabled, let aspect = settings.letterbox.aspect,
              viewport.width > 0, viewport.height > 0 else { return full }
        let height = viewport.width / CGFloat(aspect)
        guard height < viewport.height else { return full }
        return CGRect(x: 0, y: (viewport.height - height) / 2, width: viewport.width, height: height)
    }

    /// nil when cinema is off, so nothing at all gets drawn. `emphasisCenter` is the hero word's
    /// center in view points; the streak crosses it, and otherwise crosses the picture's middle.
    public static func frame(settings: CinemaSettings, viewport: CGSize, beat: Float, bass: Float,
                             emphasisCenter: CGPoint?, time: Double) -> CinemaFrame? {
        guard settings.enabled, viewport.width > 0, viewport.height > 0 else { return nil }
        let picture = pictureRect(settings: settings, viewport: viewport)

        let flareSetting = Float(min(1, max(0, settings.flare)))
        let pulse = min(1, max(0, beat))
        let strength = flareSetting == 0 ? 0 : flareSetting * (restingFlare + (1 - restingFlare) * pulse)

        // Quantize time so the grain pattern holds for one film frame, then changes.
        let step = floor(max(0, time) * grainRate)
        let seed = Float(step.truncatingRemainder(dividingBy: 4096))

        _ = bass   // reserved: the streak length may breathe with the low end later
        return CinemaFrame(
            barFraction: Double(picture.minY / viewport.height),
            vignette: Float(min(1, max(0, settings.vignette))),
            grain: Float(min(1, max(0, settings.grain))),
            grainSeed: seed,
            flare: strength,
            flareCenter: CGPoint(x: emphasisCenter?.x ?? picture.midX, y: emphasisCenter?.y ?? picture.midY),
            flareHalfWidth: Double(picture.width) * (0.35 + 0.15 * Double(pulse)))
    }
}
