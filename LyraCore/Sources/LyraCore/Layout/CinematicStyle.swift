import Foundation
import CoreGraphics

/// What a line became, for labels and diagnostics.
public struct CinematicShotInfo: Equatable, Sendable {
    public var template: String
    public var transition: String
    /// Seconds the shot's arrival takes (0 for a hard cut).
    public var entranceDuration: Double
}

/// Each lyric line is cut like a shot in a lyric video or a film title sequence: a hero word at scale
/// with the rest of the line composed around it, a slow camera move across the shot, and a quick,
/// energetic transition into it. Only the current line is on screen.
///
/// Pure and deterministic. The beat and bass in the frame add a small punch and a tiny shake, and
/// are exactly zero effect when there is no audio.
public struct CinematicStyle: LyricStyle {
    public let name = "Cinematic"

    private let forcedTemplate: ShotTemplate?
    private let forcedCamera: CameraMove?
    private let forcedTransition: ShotTransition?

    public init() {
        forcedTemplate = nil
        forcedCamera = nil
        forcedTransition = nil
    }

    /// For tests: pin the template, camera move or transition instead of choosing from the line.
    init(forcing template: ShotTemplate?, camera: CameraMove? = nil, transition: ShotTransition? = nil) {
        forcedTemplate = template
        forcedCamera = camera
        forcedTransition = transition
    }

    /// The composition chosen for line `index`, without laying anything out.
    public static func describeShot(lineIndex index: Int, in lines: [LyricLine]) -> CinematicShotInfo? {
        guard lines.indices.contains(index), !lines[index].words.isEmpty else { return nil }
        let texts = lines[index].words.map(\.text)
        let s = CinematicShots.seed(forLine: index, texts: texts)
        let transition = CinematicShots.transition(seed: s)
        return CinematicShotInfo(template: CinematicShots.template(forLine: index, in: lines).name,
                                 transition: transition.name, entranceDuration: transition.duration)
    }

    public func layout(_ frame: LyricsFrame, viewport: CGSize, config: OverlayConfig, measurer: TextMeasuring) -> [DrawItem] {
        guard let index = frame.cursor.lineIndex, frame.lines.indices.contains(index) else { return [] }
        let line = frame.lines[index]
        guard !line.isInstrumentalGap, !line.words.isEmpty, viewport.width > 0, viewport.height > 0 else { return [] }

        // The shot leaves quickly after the line is sung, so the next cut feels punchy.
        let hold = min(config.lingerAfterSung, 0.45)
        let leave = min(config.fadeOutDuration, 0.25)
        let sinceHold = frame.position - (line.sungEnd + hold)
        let exit = leave > 0 ? StyleKit.smooth(sinceHold / leave) : (sinceHold >= 0 ? 1 : 0)
        guard exit < 1 else { return [] }

        let texts = line.words.map(\.text)
        let seed = CinematicShots.seed(forLine: index, texts: texts)
        let template = forcedTemplate ?? CinematicShots.template(forLine: index, in: frame.lines)
        let move = forcedCamera ?? CinematicShots.camera(seed: seed)
        // "No entrance" in the settings (a zero fade-in) means hard cuts.
        var transition = forcedTransition ?? CinematicShots.transition(seed: seed)
        if config.fadeInDuration <= 0 { transition = .cut }

        let ctx = ShotContext(viewport: viewport, baseFont: config.font, measurer: measurer)
        let hero = EmphasisPicker.index(of: texts)
        let words = CinematicShots.build(template, texts: texts, hero: hero, seed: seed, ctx: ctx)

        let age = max(0, frame.position - line.start)
        let side = CinematicShots.side(seed: seed)
        let cam = Self.camera(move, age: age, duration: line.end - line.start, seed: seed, viewport: viewport)
        let beat = Double(min(1, max(0, frame.beat))), bass = Double(min(1, max(0, frame.bass)))
        let shake = Self.shake(position: frame.position, amount: bass, seed: seed, viewport: viewport)

        let vc = CGPoint(x: viewport.width / 2, y: viewport.height / 2)
        let T = transition.duration

        var items: [DrawItem] = []
        for w in words {
            var center = w.center
            var scale = 1.0, blur = 0.0, opacity = 1.0

            // Transition: how this item arrives.
            let delay = transition == .cut ? 0 : w.delay
            let p = T > 0 ? clamp((age - delay) / T) : 1
            let e = easeOut(p)
            switch transition {
            case .cut:
                break
            case .whip:
                center.x += CGFloat(side * 0.35) * viewport.width * CGFloat(1 - e)
                blur = 0.8 * (1 - e)
                opacity = ramp(p, over: 0.5)
            case .zoomThrough:
                let s = StyleKit.lerp(1.8, 1, e)
                center = CGPoint(x: vc.x + (center.x - vc.x) * CGFloat(s), y: vc.y + (center.y - vc.y) * CGFloat(s))
                scale *= s
                blur = 0.7 * (1 - e)
                opacity = ramp(p, over: 0.5)
            case .riseSettle:
                center.y += 0.06 * viewport.height * CGFloat(1 - e)
                let s = StyleKit.lerp(1.04, 1, e)
                center = CGPoint(x: vc.x + (center.x - vc.x) * CGFloat(s), y: vc.y + (center.y - vc.y) * CGFloat(s))
                scale *= s
                opacity = ramp(p, over: 0.6)
            }

            // Scatter phrases wait for the singer.
            if w.appearsWhenSung {
                let start = line.words[w.covers.lowerBound].start
                opacity *= StyleKit.smooth((frame.position - start) / 0.12)
            }

            // Camera: scale and pan the whole shot about the centre of the frame.
            center = CGPoint(x: vc.x + (center.x - vc.x) * CGFloat(cam.scale) + CGFloat(cam.dx),
                             y: vc.y + (center.y - vc.y) * CGFloat(cam.scale) + CGFloat(cam.dy))
            scale *= cam.scale
            center.x += CGFloat(shake.dx)
            center.y += CGFloat(shake.dy)
            if w.isEmphasis { scale *= 1 + 0.04 * beat }

            // Exit: a slight push through as the shot fades.
            opacity *= 1 - exit
            scale *= 1 + 0.05 * exit

            var item = DrawItem(
                text: w.text, font: w.font, center: center,
                size: CGSize(width: w.width, height: w.height),
                baseColor: w.isEmphasis ? config.baseColor.scaledAlpha(1.4) : config.baseColor,
                highlightColor: config.highlightColor, glowColor: config.glowColor,
                // The glow radius grows with the font size, so a huge hero needs less of it to stay crisp.
                glow: w.isEmphasis ? min(1.2, config.glow * 0.85) : config.glow * 0.4,
                progress: Self.progress(of: w.covers, in: line, cursor: frame.cursor),
                opacity: Float(clamp(opacity)), shadow: config.shadow, scale: Float(scale),
                lineIndex: index, wordIndex: w.covers.lowerBound, blur: Float(clamp(blur)), isEmphasis: w.isEmphasis)
            Self.contain(&item, in: viewport)
            items.append(item)
        }
        return items
    }

    // MARK: - Camera

    struct Camera { var scale: Double; var dx: Double; var dy: Double }

    /// A slow move that runs across the shot's own duration.
    static func camera(_ move: CameraMove, age: Double, duration: Double, seed: UInt64, viewport: CGSize) -> Camera {
        let u = clamp(age / max(1, min(8, duration)))
        let pan = 0.02
        let W = Double(viewport.width), H = Double(viewport.height)
        switch move {
        case .pushIn: return Camera(scale: 1 + 0.07 * u, dx: 0, dy: 0)
        case .pullOut: return Camera(scale: 1.07 - 0.07 * u, dx: 0, dy: 0)
        case .panLeft: return Camera(scale: 1.02, dx: StyleKit.lerp(pan * W, -pan * W, u), dy: 0)
        case .panRight: return Camera(scale: 1.02, dx: StyleKit.lerp(-pan * W, pan * W, u), dy: 0)
        case .panUp: return Camera(scale: 1.02, dx: 0, dy: StyleKit.lerp(pan * H, -pan * H, u))
        case .drift:
            let phase = Double(seed % 628) / 100
            return Camera(scale: 1.02, dx: 0.012 * W * sin(phase + u * .pi), dy: 0.012 * H * cos(phase + u * .pi * 0.8))
        }
    }

    /// A very small, deterministic shake that grows with bass; exactly zero without it.
    static func shake(position: Double, amount: Double, seed: UInt64, viewport: CGSize) -> (dx: Double, dy: Double) {
        guard amount > 0 else { return (0, 0) }
        let amp = 0.004 * Double(min(viewport.width, viewport.height)) * amount
        let a = Double(seed % 97), b = Double((seed >> 8) % 89)
        return (amp * sin(position * 47 + a), amp * cos(position * 59 + b))
    }

    // MARK: - Pieces

    /// Wipe progress of an item covering these words: a single word's own progress, or the
    /// character-weighted average for a phrase.
    static func progress(of covers: Range<Int>, in line: LyricLine, cursor: CursorState) -> Float {
        if covers.count == 1 { return StyleKit.wordProgress(covers.lowerBound, cursor) }
        var total = 0.0, done = 0.0
        for i in covers where line.words.indices.contains(i) {
            let weight = Double(max(1, line.words[i].text.count))
            total += weight
            done += weight * Double(StyleKit.wordProgress(i, cursor))
        }
        return total > 0 ? Float(done / total) : 0
    }

    /// Final guarantee that nothing leaves the frame, whatever the transition and camera did: a
    /// scale that would overflow is reduced, and the item is slid back inside.
    static func contain(_ item: inout DrawItem, in viewport: CGSize) {
        let maxWidth = viewport.width * 0.98
        let width = item.size.width * CGFloat(item.scale)
        if width > maxWidth, width > 0 { item.scale *= Float(maxWidth / width) }

        let halfW = item.size.width * CGFloat(item.scale) / 2
        item.center.x = min(max(item.center.x, halfW), max(halfW, viewport.width - halfW))
        item.center.y = min(max(item.center.y, 0), viewport.height)
    }
}

private func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
private func easeOut(_ t: Double) -> Double { 1 - pow(1 - t, 3) }
private func ramp(_ t: Double, over fraction: Double) -> Double { clamp(t / fraction) }
