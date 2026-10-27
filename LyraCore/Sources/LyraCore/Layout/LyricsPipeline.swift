import Foundation
import CoreGraphics

/// The one entry point for turning a frame into draw items: the style's layout, then the
/// entrance and exit animations. Both the desktop overlay and the player window call this.
public enum LyricsPipeline {
    public static func items(style: LyricStyle, frame: LyricsFrame, viewport: CGSize, config: OverlayConfig,
                             measurer: TextMeasuring) -> [DrawItem] {
        // Styles bake a quick fade-in and a linger-then-fade-out. "None" means the line appears
        // and leaves instantly, so those baked fades are switched off before layout.
        var effective = config
        if config.entrance == .none { effective.fadeInDuration = 0 }
        if config.exit == .none { effective.fadeOutDuration = 0 }

        let items = style.layout(frame, viewport: viewport, config: effective, measurer: measurer)
        return Animator.apply(items, frame: frame, config: config)
    }
}
