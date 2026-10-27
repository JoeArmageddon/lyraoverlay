import AppKit
import Combine
import SwiftUI
import LyraCore

/// Hosts the window's layers and accepts dropped image and video files.
final class PlayerContentView: NSView {
    var onDropFiles: (([URL]) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func supportedURLs(_ info: NSDraggingInfo) -> [URL] {
        let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        return (urls ?? []).filter(BackgroundLibraryModel.isSupported)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        supportedURLs(sender).isEmpty ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = supportedURLs(sender)
        guard !urls.isEmpty else { return false }
        onDropFiles?(urls)
        return true
    }
}

/// The standalone player: a window with a picture or looping video behind the lyrics, a glowing
/// border in the background's colors, now-playing controls, native full screen, and an option
/// to keep the Mac awake while it is open and music is playing.
///
/// The owner (the app controller) decides when to call `show()`, starts and stops the audio
/// capture, and may hide the desktop overlay while `isVisible` is true.
public final class PlayerWindowController: NSWindowController, NSWindowDelegate {
    /// Called when the window becomes or stops being visible (shown, closed, minimized, covered, on another space).
    public var onVisibilityChange: ((Bool) -> Void)?
    public private(set) var isVisible = false
    /// Whether the window is currently holding the Mac awake.
    public var isKeepingAwake: Bool { awake.isActive }

    private let renderer: MetalRenderer
    private let model: SettingsModel
    private let session: LyricsSession
    private let capture: SystemAudioCapture
    private let library: BackgroundLibrary

    private let background = BackgroundView(frame: .zero)
    private let metalView: LyricsMetalView
    private let ui = PlayerUIState()
    private let backgroundsModel: BackgroundLibraryModel
    private var hosting: NSHostingView<PlayerControlsView>!

    private let awake = KeepAwake()
    private var smoother = PaletteSmoother(timeConstant: 0.5)   // colors glide over about a second
    private var backgroundPalette: Palette?
    private var shownBackgroundID: String?
    private var lastLightTime = ProcessInfo.processInfo.systemUptime
    private let startTime = ProcessInfo.processInfo.systemUptime

    private let measurer = CoreTextMeasurer()
    private let effect = RimGlowEffect()
    private let caseCache = LyricsCaseCache()
    private let artworkProvider: ArtworkProvider
    private var shownTrackKey = ""
    /// Center of the hero word in the last frame's lyrics, in view points; the flare crosses it.
    private var lastEmphasisCenter: CGPoint?

    private var cancellables = Set<AnyCancellable>()
    private var timer: Timer?
    private var hideTimer: Timer?
    private var eventMonitor: Any?

    public init(renderer: MetalRenderer, model: SettingsModel, session: LyricsSession, capture: SystemAudioCapture,
                library: BackgroundLibrary = BackgroundLibrary(),
                artworkProvider: ArtworkProvider = PlayerArtworkProvider()) {
        self.renderer = renderer
        self.artworkProvider = artworkProvider
        self.model = model
        self.session = session
        self.capture = capture
        self.library = library
        self.metalView = LyricsMetalView(frame: .zero, renderer: renderer)
        self.backgroundsModel = BackgroundLibraryModel(library: library)

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 600),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Lyra"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // Full screen is allowed, and showing the window brings it to the Space the user is on instead
        // of leaving it on whichever desktop it was last on (or the one an app launched it from).
        window.collectionBehavior = [.fullScreenPrimary, .moveToActiveSpace]
        window.contentMinSize = NSSize(width: 480, height: 300)
        window.isReleasedWhenClosed = false
        window.acceptsMouseMovedEvents = true
        window.backgroundColor = .black
        window.center()
        // A verification run sets this so it doesn't write window positions into the user's preferences.
        if ProcessInfo.processInfo.environment["LYRA_NO_FRAME_AUTOSAVE"] == nil {
            window.setFrameAutosaveName("LyraPlayer")
        }
        super.init(window: window)
        window.delegate = self

        let container = PlayerContentView(frame: NSRect(x: 0, y: 0, width: 960, height: 600))
        container.onDropFiles = { [weak self] urls in self?.importBackgrounds(from: urls) }
        for view in [background, metalView] as [NSView] {
            view.frame = container.bounds
            view.autoresizingMask = [.width, .height]
            container.addSubview(view)
        }
        let actions = PlayerActions(
            playPause: { [weak self] in self?.send(.playPause) },
            next: { [weak self] in self?.send(.next) },
            previous: { [weak self] in self?.send(.previous) },
            toggleFullScreen: { [weak self] in self?.toggleFullScreen() })
        hosting = NSHostingView(rootView: PlayerControlsView(ui: ui, model: model, backgrounds: backgroundsModel, session: session, actions: actions))
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        window.contentView = container

        metalView.itemsProvider = { [weak self] size in self?.lyricItems(for: size) ?? [] }
        metalView.lightProvider = { [weak self] size in self?.borderLights(for: size) }
        metalView.cinemaProvider = { [weak self] size in self?.cinemaFrame(for: size) }
        background.onPaletteChange = { [weak self] palette in self?.backgroundPalette = palette }
        backgroundsModel.onImported = { [weak self] item in self?.model.settings.player.backgroundID = item.id }

        model.$settings
            .sink { [weak self] settings in self?.apply(settings.player) }
            .store(in: &cancellables)
        apply(model.settings.player)

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .leftMouseDragged, .scrollWheel, .keyDown]) { [weak self] event in
            self?.handle(event) ?? event
        }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(timer, forMode: .common)   // keeps ticking while a menu or popover is tracking
        self.timer = timer
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    deinit {
        timer?.invalidate()
        hideTimer?.invalidate()
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        awake.releaseNow()
    }

    // MARK: - Public

    public func show() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        background.setPlaybackAllowed(true)
        apply(model.settings.player)
        refresh()
        pointerActivity()
    }

    public func toggleFullScreen() {
        window?.toggleFullScreen(nil)
    }

    /// Adds files to the library and selects the last one that imported. Also used by drag and drop.
    func importBackgrounds(from urls: [URL]) {
        backgroundsModel.importFiles(urls)
    }

    // MARK: - Settings

    private func apply(_ player: PlayerSettings) {
        if player.backgroundID != shownBackgroundID {
            shownBackgroundID = player.backgroundID
            background.show(library.item(id: player.backgroundID), library: library)
        }
        background.dim = player.dim
        background.blur = player.blur
        background.fill = player.fill
        window?.level = player.keepOnTop ? .floating : .normal
    }

    // MARK: - What to draw each frame

    /// The one place the layout is chosen: the selected style plus the entrance and exit animations.
    private func layout(_ frame: LyricsFrame, viewport: CGSize, config: OverlayConfig) -> [DrawItem] {
        LyricsPipeline.items(style: LyricStyles.style(id: model.settings.styleID), frame: frame, viewport: viewport,
                             config: config, measurer: measurer)
    }

    /// What the music is doing right now, or nil when audio capture isn't running.
    private func currentFeatures() -> AudioFeatures? {
        capture.state == .capturing ? capture.tracker.features() : nil
    }

    private func lyricItems(for viewport: CGSize) -> [DrawItem] {
        lastEmphasisCenter = nil
        let state = session.current
        guard let cursor = state.cursor, let document = state.document else { return [] }
        let settings = model.settings
        // With letterbox bars the lyrics are composed for the picture area and then moved inside it;
        // with cinema off the region is the whole view and nothing moves.
        let region = PlayerFrameBuilder.lyricRegion(cinema: settings.player.cinema, viewport: viewport)
        let config = PlayerFrameBuilder.lyricConfig(
            base: settings.overlay, albumPalette: state.palette, useArtworkColors: settings.useArtworkColors,
            viewportWidth: region.width, lyricsScale: settings.player.lyricsScale)
        let doc = caseCache.document(document, trackKey: state.trackKey, textCase: config.textCase)
        let position = state.position(offset: config.latencyOffset)
        let frame = PlayerFrameBuilder.lyricsFrame(lines: doc.lines, cursor: cursor.state(at: position), position: position,
                                                   features: currentFeatures())
        let items = PlayerFrameBuilder.shifted(layout(frame, viewport: region.size, config: config), by: region.origin)
        lastEmphasisCenter = PlayerFrameBuilder.emphasisCenter(in: items)
        return items
    }

    /// The film-look finishing for this frame. The view asks for the lyrics first in the same draw,
    /// so `lastEmphasisCenter` is the hero word of the frame being drawn.
    private func cinemaFrame(for viewport: CGSize) -> CinemaFrame? {
        let features = currentFeatures()
        return CinemaEffect.frame(settings: model.settings.player.cinema, viewport: viewport,
                                  beat: features?.beat ?? 0, bass: features?.bass ?? 0,
                                  emphasisCenter: lastEmphasisCenter,
                                  time: ProcessInfo.processInfo.systemUptime - startTime)
    }

    private func borderLights(for viewport: CGSize) -> LightParams? {
        let state = session.current
        let player = model.settings.player
        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(0.25, now - lastLightTime)
        lastLightTime = now

        let source = PlayerFrameBuilder.borderSource(background: backgroundPalette, album: state.palette,
                                                     followBackground: player.borderFollowsBackground)
        var palette: Palette?
        if let source { palette = smoother.update(target: source, dt: dt) } else { smoother.reset() }

        let features = capture.state == .capturing ? capture.tracker.features() : nil
        return PlayerFrameBuilder.lightParams(effect: effect, features: features, palette: palette, config: player.border,
                                              viewportWidth: viewport.width, time: now - startTime)
    }

    // MARK: - Periodic refresh

    private func computeVisible() -> Bool {
        guard let window else { return false }
        return window.isVisible && !window.isMiniaturized && window.occlusionState.contains(.visible)
    }

    private func refresh() {
        let visible = computeVisible()
        if visible != isVisible {
            isVisible = visible
            onVisibilityChange?(visible)
        }
        let state = session.current
        let playing = state.snapshot.isPlaying

        // Drawing runs whenever the window can be seen, so the border and the current line stay up while
        // paused (at a low rate); a hidden window draws nothing and its video is paused.
        metalView.setActive(visible)
        let fps = playing ? 60 : 12
        if metalView.preferredFramesPerSecond != fps { metalView.preferredFramesPerSecond = fps }
        background.setPlaybackAllowed(visible)
        awake.update(enabled: model.settings.player.keepAwake, windowVisible: visible, playing: playing)

        updateUI(state)
        if Self.debug {
            NSLog("Lyra player: win.isVisible=\(window?.isVisible ?? false) occlusion=\(window?.occlusionState.rawValue ?? 99) mini=\(window?.isMiniaturized ?? false) appActive=\(NSApp.isActive) onSpace=\(window?.isOnActiveSpace ?? false) visible=\(visible) active=\(metalView.isActive) paused=\(metalView.isPaused) playing=\(playing) status=\(state.status) metalFrame=\(metalView.frame) hidden=\(metalView.isHidden) awake=\(awake.isActive) bg=\(shownBackgroundID ?? "-") items=\(lyricItems(for: metalView.bounds.size).count)")
        }
    }

    /// `LYRA_PLAYER_DEBUG=1` logs the refresh loop's view of things, for diagnosing a blank window.
    private static let debug = ProcessInfo.processInfo.environment["LYRA_PLAYER_DEBUG"] != nil

    private func updateUI(_ state: SessionState) {
        ui.isPlaying = state.snapshot.isPlaying
        switch state.status {
        case .idle: ui.status = "Play something in Spotify or Music"
        case .loading: ui.status = "Finding lyrics…"
        case .unavailable: ui.status = "No synced lyrics for this track"
        case .ready: ui.status = nil
        }
        guard state.trackKey != shownTrackKey else { return }
        shownTrackKey = state.trackKey
        ui.title = state.snapshot.track?.title ?? ""
        ui.artist = state.snapshot.track?.artist ?? ""
        ui.art = nil
        guard let track = state.snapshot.track else { return }
        let key = state.trackKey
        Task { [weak self, artworkProvider] in
            let started = Date()
            guard let image = await artworkProvider.artwork(for: track) else {
                if Self.debug { NSLog("Lyra player: no artwork for \(track.title)") }
                return
            }
            if Self.debug { NSLog("Lyra player: artwork \(image.width)x\(image.height) after \(String(format: "%.2f", Date().timeIntervalSince(started)))s") }
            await MainActor.run {
                guard let self, self.shownTrackKey == key else { return }   // the track may have changed meanwhile
                self.ui.art = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            }
        }
    }

    private func send(_ command: PlayerCommand) {
        // With nothing playing, press the button on Music: it is the likelier thing to start.
        let player = session.current.snapshot.track?.player ?? .appleMusic
        Task { _ = await PlayerControl.send(command, to: player) }
    }

    // MARK: - Pointer, keys, auto-hide

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard event.window === window else { return event }
        pointerActivity()
        // Space toggles play/pause, unless the user is typing into something.
        if event.type == .keyDown, event.keyCode == 49, !(window?.firstResponder is NSText), !ui.pickerShown {
            send(.playPause)
            return nil
        }
        return event
    }

    /// Shows the controls and starts the countdown to hide them again (and the cursor, in full screen).
    private func pointerActivity() {
        ui.controlsVisible = true
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
            guard let self else { return }
            if self.ui.pickerShown { return self.pointerActivity() }   // never hide while the picker is open
            self.ui.controlsVisible = false
            if self.ui.isFullScreen { NSCursor.setHiddenUntilMouseMoves(true) }
        }
    }

    // MARK: - NSWindowDelegate

    public func windowWillClose(_ notification: Notification) {
        awake.releaseNow()
        background.setPlaybackAllowed(false)
        metalView.setActive(false)
        hideTimer?.invalidate()
        if isVisible {
            isVisible = false
            onVisibilityChange?(false)
        }
    }

    public func windowDidEnterFullScreen(_ notification: Notification) {
        ui.isFullScreen = true
        pointerActivity()
    }

    public func windowDidExitFullScreen(_ notification: Notification) {
        ui.isFullScreen = false
        NSCursor.unhide()
        pointerActivity()
    }

    public func windowDidMiniaturize(_ notification: Notification) { refresh() }
    public func windowDidDeminiaturize(_ notification: Notification) { refresh() }
    public func windowDidChangeOcclusionState(_ notification: Notification) { refresh() }
}
