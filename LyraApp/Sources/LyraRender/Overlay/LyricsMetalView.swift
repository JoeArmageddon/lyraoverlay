import AppKit
import MetalKit
import LyraCore

/// A transparent Metal view that asks `itemsProvider` what to draw each frame.
/// It only runs its display link while `isActive`, so an idle overlay costs nothing.
final class LyricsMetalView: MTKView, MTKViewDelegate {
    private let renderer: MetalRenderer

    /// Called on the main thread once per frame with the view size in points.
    var itemsProvider: (CGSize) -> [DrawItem] = { _ in [] }
    /// Called once per frame; nil draws no edge lighting.
    var lightProvider: (CGSize) -> LightParams? = { _ in nil }
    /// Called once per frame; nil draws no backdrop panel behind the lyrics.
    var panelProvider: (CGSize) -> PanelParams? = { _ in nil }
    /// Called once per frame; nil encodes nothing (no bars, vignette, grain or flare).
    var cinemaProvider: (CGSize) -> CinemaFrame? = { _ in nil }

    private(set) var isActive = false

    init(frame: NSRect, renderer: MetalRenderer) {
        self.renderer = renderer
        super.init(frame: frame, device: renderer.device)
        colorPixelFormat = MetalRenderer.pixelFormat
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        framebufferOnly = true
        preferredFramesPerSecond = 60
        (layer as? CAMetalLayer)?.isOpaque = false
        delegate = self
        // Start idle: draw only on demand until activated.
        isPaused = true
        enableSetNeedsDisplay = true
    }

    required init(coder: NSCoder) { fatalError("not used") }

    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        if active {
            enableSetNeedsDisplay = false
            isPaused = false
        } else {
            // One last draw so the final frame is cleared, then stop the display link.
            enableSetNeedsDisplay = true
            isPaused = true
            setNeedsDisplay(bounds)
        }
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let pass = currentRenderPassDescriptor,
              let drawable = currentDrawable,
              let cmd = renderer.queue.makeCommandBuffer(),
              let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { return }
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        // The lyrics are asked for first: the cinema frame aims its flare at the emphasized word.
        let items = isActive ? itemsProvider(bounds.size) : []
        let cinema = isActive ? cinemaProvider(bounds.size) : nil
        // Lights go first so the lyrics draw on top of them; with letterbox bars they hug the picture.
        if isActive, let lights = lightProvider(bounds.size) {
            if let cinema, cinema.barFraction > 0 {
                renderer.encodeLights(lights, in: cinema.pictureRect(in: bounds.size), of: bounds.size, scale: scale, encoder: enc)
            } else {
                renderer.encodeLights(lights, viewport: bounds.size, scale: scale, encoder: enc)
            }
        }
        // The backdrop (corner mode) stays up between lines so the card doesn't blink.
        if isActive, let panel = panelProvider(bounds.size) {
            renderer.encodePanel(panel, viewport: bounds.size, scale: scale, encoder: enc)
        }
        renderer.encode(items, viewport: bounds.size, scale: scale, encoder: enc)
        // Vignette, grain and bars sit over everything the Metal layer draws.
        if let cinema { renderer.encodeCinema(cinema, viewport: bounds.size, scale: scale, encoder: enc) }
        enc.endEncoding()
        cmd.present(drawable)
        cmd.commit()
    }
}
