import AppKit
import AVFoundation
import CoreImage
import QuartzCore
import LyraCore

/// Draws the player window's background: a gradient, a picture, or a muted looping video, with
/// dim and blur on top. It also reports the background's colors, and for video keeps sampling
/// them as the picture changes, so the window's border can follow.
final class BackgroundView: NSView {
    /// Colors of what is on screen now: the cached palette for pictures and gradients, the latest
    /// sampled frame for video. nil until known.
    private(set) var palette: Palette?
    /// Called on the main thread whenever `palette` is set (once for stills, about every 1.5 s for video).
    var onPaletteChange: ((Palette) -> Void)?

    /// 0...0.85 black overlay.
    var dim = 0.35 { didSet { applyDim() } }
    /// 0...40 points of Gaussian blur.
    var blur = 0.0 { didSet { applyBlur() } }
    var fill = BackgroundFill.fill { didSet { applyFill() } }

    private(set) var currentItem: BackgroundItem?
    /// Number of video frames sampled so far; lets tests and diagnostics see that sampling runs.
    private(set) var videoSampleCount = 0
    var isPlayingVideo: Bool { player?.rate ?? 0 > 0 }

    // The content sits in `contentLayer`, which is larger than the view by a margin when blurred,
    // so the blur's soft transparent edge falls outside the visible bounds instead of showing as a halo.
    private let contentLayer = CALayer()
    private let dimLayer = CALayer()
    private var imageLayer: CALayer?
    private var gradientLayer: CAGradientLayer?
    private var playerLayer: AVPlayerLayer?
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var videoOutput: AVPlayerItemVideoOutput?
    private var outputItem: AVPlayerItem?
    private var itemObservation: NSKeyValueObservation?
    private var sampleTimer: Timer?
    private var generation = 0
    private var windowObservers: [NSObjectProtocol] = []
    private var playbackAllowed = true

    private static let sampleQueue = DispatchQueue(label: "lyra.background.sample", qos: .utility)
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerUsesCoreImageFilters = true   // needed for the blur filter on a layer-backed view
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(contentLayer)
        dimLayer.backgroundColor = NSColor.black.withAlphaComponent(dim).cgColor
        layer?.addSublayer(dimLayer)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    deinit {
        stopVideo()
        removeWindowObservers()
    }

    // MARK: - Showing an item

    func show(_ item: BackgroundItem, library: BackgroundLibrary) {
        generation += 1
        let token = generation
        clearContent()
        currentItem = item

        switch item.kind {
        case .gradient:
            showGradient(item)
        case .image:
            showImage(item, library: library, token: token)
        case .video:
            showVideo(item, library: library)
        }
        applyFill()
        applyBlur()
        needsLayout = true
    }

    /// Stops the work and drops what is shown.
    private func clearContent() {
        stopVideo()
        imageLayer?.removeFromSuperlayer(); imageLayer = nil
        gradientLayer?.removeFromSuperlayer(); gradientLayer = nil
        playerLayer?.removeFromSuperlayer(); playerLayer = nil
        palette = nil
    }

    private func publish(_ palette: Palette?) {
        guard let palette else { return }
        self.palette = palette
        onPaletteChange?(palette)
    }

    // MARK: - Gradient

    private func showGradient(_ item: BackgroundItem) {
        let gradient = CAGradientLayer()
        let colors = item.stops.isEmpty ? BackgroundLibrary.builtIns[0].stops : item.stops
        gradient.colors = colors.map { CGColor(srgbRed: CGFloat($0.r), green: CGFloat($0.g), blue: CGFloat($0.b), alpha: 1) }
        // Layer space is y-up: (0,1) is the top-left corner.
        gradient.startPoint = CGPoint(x: 0, y: 1)
        gradient.endPoint = CGPoint(x: 1, y: 0)

        // A slow drift of the gradient axis. Core Animation runs it on the compositor, so it costs no CPU.
        let start = CABasicAnimation(keyPath: "startPoint")
        start.fromValue = CGPoint(x: 0, y: 1); start.toValue = CGPoint(x: 0.3, y: 0.7)
        let end = CABasicAnimation(keyPath: "endPoint")
        end.fromValue = CGPoint(x: 1, y: 0); end.toValue = CGPoint(x: 0.7, y: 0.3)
        for animation in [start, end] {
            animation.duration = 20
            animation.autoreverses = true
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        }
        gradient.add(start, forKey: "drift-start")
        gradient.add(end, forKey: "drift-end")

        contentLayer.addSublayer(gradient)
        gradientLayer = gradient
        publish(item.palette ?? BackgroundItem.gradientPalette(colors))
    }

    // MARK: - Image

    private func showImage(_ item: BackgroundItem, library: BackgroundLibrary, token: Int) {
        guard let url = library.fileURL(for: item) else { return fallBack() }
        // Decoding a large photo takes a moment; do it off the main thread, and ignore the result
        // if something else was chosen meanwhile.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let image = Self.decodeImage(at: url, maxPixels: 3840)
            let palette = item.palette ?? image.flatMap { PaletteExtractor.extract(from: $0) }
            DispatchQueue.main.async {
                guard let self, token == self.generation else { return }
                guard let image else { return self.fallBack() }
                let layer = CALayer()
                layer.contents = image
                layer.contentsScale = self.window?.backingScaleFactor ?? 2
                self.contentLayer.addSublayer(layer)
                self.imageLayer = layer
                self.applyFill()
                self.needsLayout = true
                self.publish(palette)
            }
        }
    }

    private static func decodeImage(at url: URL, maxPixels: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0 else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// The file is gone or unreadable: show the first built-in instead of an empty window.
    private func fallBack() {
        let item = BackgroundLibrary.builtIns[0]
        clearContent()
        currentItem = item
        showGradient(item)
        needsLayout = true
    }

    // MARK: - Video

    private func showVideo(_ item: BackgroundItem, library: BackgroundLibrary) {
        guard let url = library.fileURL(for: item) else { return fallBack() }
        let player = AVQueuePlayer()
        player.isMuted = true
        // The video itself must not keep the display awake: that is the player window's own, separate choice.
        player.preventsDisplaySleepDuringVideoPlayback = false
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(asset: AVURLAsset(url: url)))   // gapless loop

        let layer = AVPlayerLayer(player: player)
        contentLayer.addSublayer(layer)
        playerLayer = layer
        self.player = player

        // The looper swaps in a fresh item for every pass, and an output belongs to one item.
        itemObservation = player.observe(\.currentItem, options: [.initial, .new]) { [weak self] player, _ in
            let item = player.currentItem
            DispatchQueue.main.async { self?.attachOutput(to: item) }
        }
        publish(item.palette)   // the cached palette until the first sample arrives
        updatePlayback()
    }

    private func attachOutput(to item: AVPlayerItem?) {
        if let old = outputItem, let output = videoOutput { old.remove(output) }
        videoOutput = nil
        outputItem = nil
        guard let item else { return }
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        item.add(output)
        videoOutput = output
        outputItem = item
    }

    private func stopVideo() {
        sampleTimer?.invalidate()
        sampleTimer = nil
        itemObservation?.invalidate()
        itemObservation = nil
        if let old = outputItem, let output = videoOutput { old.remove(output) }
        videoOutput = nil
        outputItem = nil
        player?.pause()
        looper?.disableLooping()
        looper = nil
        player?.removeAllItems()
        player = nil
    }

    /// Takes the newest decoded frame, shrinks it and extracts its palette off the main thread.
    private func sampleFrame() {
        guard let output = videoOutput else { return }
        let time = output.itemTime(forHostTime: CACurrentMediaTime())
        guard output.hasNewPixelBuffer(forItemTime: time),
              let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) else { return }
        let token = generation
        Self.sampleQueue.async { [weak self] in
            guard let image = Self.smallImage(from: buffer), let palette = PaletteExtractor.extract(from: image) else { return }
            DispatchQueue.main.async {
                guard let self, token == self.generation else { return }
                self.videoSampleCount += 1
                self.publish(palette)
            }
        }
    }

    private static func smallImage(from buffer: CVPixelBuffer) -> CGImage? {
        let image = CIImage(cvPixelBuffer: buffer)
        let scale = 96 / max(image.extent.width, 1)
        return ciContext.createCGImage(image.transformed(by: CGAffineTransform(scaleX: scale, y: scale)),
                                       from: CGRect(x: 0, y: 0, width: image.extent.width * scale, height: image.extent.height * scale))
    }

    // MARK: - Playback follows visibility

    /// The window controller turns this off when its window closes. Even when allowed, playback
    /// still pauses while the window is minimized or fully covered.
    func setPlaybackAllowed(_ allowed: Bool) {
        playbackAllowed = allowed
        updatePlayback()
    }

    /// Tests set this to exercise playback without a window the system reports as visible.
    var visibilityOverride: Bool? { didSet { updatePlayback() } }

    private func updatePlayback() {
        guard let player else { return }
        let visible = visibilityOverride
            ?? window.map { $0.isVisible && !$0.isMiniaturized && $0.occlusionState.contains(.visible) }
            ?? false
        if playbackAllowed, visible {
            player.play()
            if sampleTimer == nil {
                sampleTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.sampleFrame() }
            }
        } else {
            player.pause()
            sampleTimer?.invalidate()
            sampleTimer = nil
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeWindowObservers()
        guard let window else { return updatePlayback() }
        let center = NotificationCenter.default
        let names: [Notification.Name] = [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
                                          NSWindow.didDeminiaturizeNotification, NSWindow.willCloseNotification]
        windowObservers = names.map { name in
            center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in self?.updatePlayback() }
        }
        updatePlayback()
    }

    private func removeWindowObservers() {
        windowObservers.forEach { NotificationCenter.default.removeObserver($0) }
        windowObservers.removeAll()
    }

    // MARK: - Layout and look

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let margin = CGFloat(blur * 2)
        contentLayer.frame = bounds.insetBy(dx: -margin, dy: -margin)
        for sub in contentLayer.sublayers ?? [] { sub.frame = contentLayer.bounds }
        dimLayer.frame = bounds
        CATransaction.commit()
    }

    private func applyDim() {
        let alpha = min(max(dim, 0), 0.85)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dimLayer.backgroundColor = NSColor.black.withAlphaComponent(alpha).cgColor
        CATransaction.commit()
    }

    private func applyBlur() {
        let radius = min(max(blur, 0), 40)
        if radius > 0.1, let filter = CIFilter(name: "CIGaussianBlur", parameters: [kCIInputRadiusKey: radius]) {
            contentLayer.filters = [filter]
        } else {
            contentLayer.filters = nil
        }
        needsLayout = true
    }

    private func applyFill() {
        imageLayer?.contentsGravity = fill == .fill ? .resizeAspectFill : .resizeAspect
        playerLayer?.videoGravity = fill == .fill ? .resizeAspectFill : .resizeAspect
    }
}
