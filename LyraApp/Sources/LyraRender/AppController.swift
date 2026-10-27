import AppKit
import Carbon.HIToolbox
import LyraCore

/// Wires now-playing, lyrics, audio, layout and the overlay windows together, and owns the menu bar item.
public final class AppController: NSObject, NSMenuDelegate, NSApplicationDelegate {
    private let session: LyricsSession
    /// The player's own artwork first, then Apple's public search for tracks it has none for.
    private let artworkProvider: ArtworkProvider
    private let artworkSwitch = ArtworkLookupSwitch()
    private let store = SettingsStore()
    private let model: SettingsModel
    private let measurer = CoreTextMeasurer()
    private let lightEffect: LightEffect = RimGlowEffect()
    private let capture = SystemAudioCapture()
    private let renderer: MetalRenderer
    private var overlay: OverlayManager!
    private var statusItem: NSStatusItem!
    private var settingsWindow: SettingsWindowController?
    private var playerWindow: PlayerWindowController?
    private let backgroundLibrary = BackgroundLibrary()
    /// Whether the player window is on screen; drives hiding the desktop overlay and the audio capture.
    private var playerOpen = false
    private var timer: Timer?
    private var saveWork: DispatchWorkItem?
    /// False for demo runs that must not touch the user's saved settings.
    private var persistSettings = true
    /// Set by `showOverlayDemo`: a fixed sample document drawn without any music playing.
    private var demoDocument: LyricsDocument?
    private var cornerHotKey: GlobalHotKey?

    /// Song-aware theming: picks a theme from genre, cover art and the sound of the track.
    private let autoTheme: AutoThemeEngine
    private var applyingAuto = false
    private var autoTrackKey = ""
    private var autoHadPalette = false

    private var styleCache: [String: LyricStyle] = [:]
    private var caseCache: (key: String, doc: LyricsDocument)?

    private let clockStart = ProcessInfo.processInfo.systemUptime
    private var lastPlaying = Date.distantPast
    private var lastCaptureAttempt = Date.distantPast
    /// How long after playback stops the audio capture keeps running, so brief pauses don't thrash it.
    /// With the Core Audio tap a restart is silent (no consent alert), so this is only about not
    /// churning devices on a short pause.
    private let captureLinger: TimeInterval = 120
    private let captureRetryDelay: TimeInterval = 5

    private var settings: AppSettings {
        get { model.settings }
        set { model.settings = newValue }
    }

    public override init() {
        guard let renderer = MetalRenderer() else {
            fatalError("Lyra needs a Metal-capable GPU.")
        }
        // Fonts the user imported earlier must be registered before any text is measured.
        FontCatalog.registerUserFonts()
        self.renderer = renderer
        let loaded = store.load()
        self.model = SettingsModel(settings: loaded)

        let lookup = artworkSwitch
        lookup.isEnabled = loaded.onlineArtwork
        let provider = ChainedArtworkProvider([
            PlayerArtworkProvider(),
            ITunesArtworkProvider(isEnabled: { lookup.isEnabled }),
        ])
        self.artworkProvider = provider
        self.session = LyricsSession(artworkProvider: provider)
        self.autoTheme = AutoThemeEngine(settings: loaded.autoTheme, themeIDs: model.themes.map(\.id))
        super.init()

        model.onChange = { [weak self] settings in self?.settingsChanged(settings) }
        overlay = OverlayManager(
            renderer: renderer,
            itemsProvider: { [weak self] viewport in self?.items(for: viewport) ?? [] },
            lightProvider: { [weak self] viewport in self?.lights(for: viewport) })
        overlay.level = settings.level
        overlay.allDisplays = settings.allDisplays
        // In corner mode the overlay windows shrink to a small card and a backdrop panel is drawn.
        overlay.frameProvider = { [weak self] screen in self?.overlayFrame(for: screen) ?? screen.frame }
        overlay.panelProvider = { [weak self] size in self?.cornerBackdrop(for: size) }
        applyVisibility()
        buildStatusItem()
    }

    public func start() {
        session.onProblem = { kind, error in NSLog("Lyra: \(kind) problem: \(error)") }
        capture.onStateChange = { state in NSLog("Lyra: audio capture \(state)") }
        session.start()
        overlay.rebuild()

        // ⌃⌥L toggles corner mode from any app. If another app already owns the combination, the
        // menu item still works.
        cornerHotKey = GlobalHotKey(keyCode: kVK_ANSI_L, modifiers: controlKey | optionKey) { [weak self] in
            self?.settings.corner.enabled.toggle()
        }

        NSApp.delegate = self
        NSApp.mainMenu = MainMenu.build(target: self, openSettings: #selector(openSettings),
                                        openPlayer: #selector(openPlayer), toggleFullScreen: #selector(toggleFullScreenPlayer))
        if settings.player.openAtLaunch { showPlayer() }

        // Cheap poll: decides whether the overlay and the audio capture need to be running.
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in self?.refresh() }
    }

    // MARK: - Player window

    /// Creates the player window on first use and brings it to the front.
    private func showPlayer() {
        if playerWindow == nil {
            let controller = PlayerWindowController(renderer: renderer, model: model, session: session,
                                                    capture: capture, library: backgroundLibrary,
                                                    artworkProvider: artworkProvider)
            controller.onVisibilityChange = { [weak self] visible in
                self?.playerOpen = visible
                self?.applyVisibility()
            }
            playerWindow = controller
        }
        playerWindow?.show()
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - NSApplicationDelegate

    /// Clicking the Dock icon with no window open brings the player back.
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !(playerWindow?.isVisible ?? false) { showPlayer() }
        return true
    }

    /// Closing the player must not quit Lyra: the overlay and the menu bar item keep running.
    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    public func stop() {
        timer?.invalidate()
        saveWork?.perform()   // flush a pending settings save
        session.stop()
        Task { await capture.stop() }
    }

    /// Opens the settings window (also reachable from the menu with ⌘,).
    public func showSettings(tab: String = "themes") {
        if settingsWindow == nil { settingsWindow = SettingsWindowController(model: model, renderer: renderer, initialTab: tab) }
        settingsWindow?.show()
    }

    /// Renders one settings tab to a PNG without showing anything on screen, for checking the UI
    /// without screen-recording access. `tab` is themes, lyrics, lights or general.
    public func snapshotSettings(tab: String, to url: URL, size: CGSize = CGSize(width: 700, height: 900)) -> Bool {
        let controller = SettingsWindowController(model: model, renderer: renderer, initialTab: tab)
        guard let window = controller.window else { return false }
        window.setContentSize(size)
        // An invisible, non-key window can resolve text and background colors from different
        // appearances, so pin one for a consistent snapshot.
        window.appearance = NSAppearance(named: .darkAqua)
        window.alphaValue = 0          // laid out and drawn, but invisible to the user
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))   // let SwiftUI lay out and the preview draw

        guard let view = window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
        window.effectiveAppearance.performAsCurrentDrawingAppearance {
            view.cacheDisplay(in: view.bounds, to: rep)
        }
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        window.orderOut(nil)
        return (try? png.write(to: url)) != nil
    }

    // MARK: - Settings

    /// Runs on every edit, including each tick of a slider drag, so saving is debounced.
    private func settingsChanged(_ settings: AppSettings) {
        autoTheme.settings = settings.autoTheme
        if !settings.autoTheme.enabled { AutoThemeStatus.shared.clear() }
        if !applyingAuto, model.activeThemeID != autoTheme.activeThemeID {
            // The user picked a theme or edited the look: leave it alone until the next track.
            autoTheme.userChoseTheme(now: ProcessInfo.processInfo.systemUptime)
            autoTheme.activeThemeID = model.activeThemeID
        }
        artworkSwitch.isEnabled = settings.onlineArtwork
        overlay.level = settings.level
        overlay.allDisplays = settings.allDisplays
        overlay.relayout()   // corner mode, card size and corner all change the window frames
        applyVisibility()

        saveWork?.cancel()
        let work = DispatchWorkItem { [store, weak self] in
            guard let self, self.persistSettings else { return }
            store.save(self.model.settings)
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    // MARK: - Drawing

    private func style(id: String) -> LyricStyle {
        if let cached = styleCache[id] { return cached }
        let made = LyricStyles.style(id: id)
        styleCache[id] = made
        return made
    }

    /// Lyrics with the chosen letter case applied, cached so it isn't recomputed every frame.
    private func document(for state: SessionState, textCase: TextCase) -> LyricsDocument? {
        guard let doc = state.document else { return nil }
        if textCase == .asWritten { return doc }
        let key = "\(state.trackKey)|\(textCase.rawValue)"
        if let cached = caseCache, cached.key == key { return cached.doc }
        let mapped = doc.applying(textCase)
        caseCache = (key, mapped)
        return mapped
    }

    private func items(for viewport: CGSize) -> [DrawItem] {
        if let demo = demoDocument { return demoItems(demo, viewport: viewport) }
        let state = session.current
        guard settings.lyricsVisible, state.snapshot.isPlaying, let cursor = state.cursor else { return [] }
        // Lyric colors follow the album art when it is available and the option is on.
        var config = ThemeResolver.resolve(settings.overlay, palette: state.palette, useArtworkColors: settings.useArtworkColors)
        let cornerMode = settings.corner.enabled
        // Corner mode is a compact caption: always the plain Karaoke Line style, sized for the card.
        if cornerMode { config = CornerOverlay.config(from: config, settings: settings.corner) }
        guard let doc = document(for: state, textCase: config.textCase) else { return [] }
        let position = state.position(offset: config.latencyOffset)
        // Beat and bass drive punch and camera shake in styles that use them; zero without audio.
        let features = capture.state == .capturing ? capture.tracker.features() : nil
        let frame = LyricsFrame(lines: doc.lines, cursor: cursor.state(at: position), position: position,
                                beat: features?.beat ?? 0, bass: features?.bass ?? 0)
        // The pipeline runs the style, then adds the chosen entrance and exit animations.
        return LyricsPipeline.items(style: style(id: cornerMode ? "karaoke" : settings.styleID), frame: frame,
                                    viewport: viewport, config: config, measurer: measurer)
    }

    /// The overlay window's frame on a screen: the whole screen, or the corner card clear of the
    /// menu bar and Dock.
    private func overlayFrame(for screen: NSScreen) -> NSRect {
        settings.corner.enabled ? CornerOverlay.frame(in: screen.visibleFrame, settings: settings.corner) : screen.frame
    }

    private func cornerBackdrop(for size: CGSize) -> PanelParams? {
        settings.corner.enabled ? CornerOverlay.backdrop(for: settings.corner, size: size) : nil
    }

    private func lights(for viewport: CGSize) -> LightParams? {
        let state = session.current
        // No edge glow in corner mode: the overlay window is only a small card.
        guard state.snapshot.isPlaying, !settings.corner.enabled else { return nil }
        // Without audio capture the effect falls back to a slow breathing glow.
        let features = capture.state == .capturing ? capture.tracker.features() : nil
        let (primary, secondary) = lightColors(for: state)
        let input = LightInput(features: features, primary: primary, secondary: secondary,
                               time: ProcessInfo.processInfo.systemUptime - clockStart)
        return lightEffect.params(input, config: settings.lights)
    }

    private func lightColors(for state: SessionState) -> (RGBA, RGBA) {
        guard settings.lights.useArtworkColors, let palette = state.palette else {
            return (RimGlowEffect.defaultPrimary, RimGlowEffect.defaultSecondary)
        }
        return (palette.lightPrimary, palette.lightSecondary)
    }

    // MARK: - Activity

    private func applyVisibility() {
        // The window stays up for the lights even when the lyrics are hidden, and steps aside
        // while the player window shows the lyrics itself.
        let wanted = settings.lyricsVisible || lightsShown
        let playerCovers = playerOpen && settings.player.hideOverlayWhenOpen
        overlay.isVisible = wanted && !playerCovers
    }

    /// Edge lights are drawn only by the full-screen overlay, never in corner mode.
    private var lightsShown: Bool { settings.lights.enabled && !settings.corner.enabled }

    private func refresh() {
        let state = session.current
        let playing = state.snapshot.isPlaying
        if playing { lastPlaying = Date() }

        if demoDocument != nil { overlay.setActive(true); return }
        let lyricsShown = settings.lyricsVisible && state.status == .ready
        overlay.setActive(playing && (lyricsShown || lightsShown))
        updateCapture(playing: playing)
        driveAutoTheme(state: state, playing: playing)
    }

    /// Feeds the auto-theme engine with what is playing; it decides when the look should change.
    private func driveAutoTheme(state: SessionState, playing: Bool) {
        guard settings.autoTheme.enabled, demoDocument == nil else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if state.trackKey != autoTrackKey {
            autoTrackKey = state.trackKey
            autoHadPalette = state.palette != nil
            autoTheme.activeThemeID = model.activeThemeID
            if state.snapshot.track == nil { AutoThemeStatus.shared.clear() }
            applyAuto(autoTheme.trackChanged(track: state.snapshot.track, palette: state.palette, now: now))
            return
        }
        guard playing else { return }
        let position = state.position()
        if !autoHadPalette, let palette = state.palette {
            autoHadPalette = true
            applyAuto(autoTheme.palette(palette, now: now, position: position))
        }
        if capture.state == .capturing {
            applyAuto(autoTheme.audio(features: capture.tracker.features(), now: now, position: position))
        }
    }

    private func applyAuto(_ decision: ThemeDecision?) {
        guard let decision, let theme = model.themes.first(where: { $0.id == decision.themeID }) else { return }
        applyingAuto = true
        model.apply(theme)
        applyingAuto = false
        autoTheme.activeThemeID = theme.id
        AutoThemeStatus.shared.update(decision, themeName: theme.name)
    }

    /// Runs the audio capture only while it is useful: lights on, and music playing (or just paused).
    private func updateCapture(playing: Bool) {
        // The player's border reacts to the music too, so an open player needs the capture as well.
        let lightsUseAudio = lightsShown || (playerOpen && settings.player.border.enabled)
        let wanted = lightsUseAudio && Date().timeIntervalSince(lastPlaying) < captureLinger
        switch capture.state {
        case .capturing:
            if !wanted { Task { await capture.stop() } }
        case .stopped:
            if wanted { startCapture() }
        case .failed:
            // Transient failures (the stream was torn down) retry; permission problems wait for the user.
            if wanted, Date().timeIntervalSince(lastCaptureAttempt) > captureRetryDelay { startCapture() }
        case .starting, .permissionDenied, .noSignal:   // .noSignal keeps running and recovers by itself
            break
        }
    }

    private func startCapture() {
        lastCaptureAttempt = Date()
        Task { await capture.start() }
    }

    // MARK: - Menu

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "Lyra")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let state = session.current

        let title = state.snapshot.track.map { "\($0.title) — \($0.artist)" } ?? "Nothing playing"
        menu.addItem(disabled: title)
        menu.addItem(disabled: lyricsStatusText(state))
        menu.addItem(disabled: audioStatusText())
        if capture.state == .permissionDenied || capture.state == .noSignal {
            menu.addAction("Allow Audio Access…", #selector(openAudioPermissions), target: self)
        } else if case .failed = capture.state {
            menu.addAction("Retry Audio Capture", #selector(retryCapture), target: self)
        }
        menu.addItem(.separator())

        menu.addAction("Open Player", #selector(openPlayer), target: self, key: "p")
        menu.addAction("Full Screen Player", #selector(toggleFullScreenPlayer), target: self)
        if playerWindow?.isKeepingAwake == true { menu.addItem(disabled: "Keeping your Mac awake") }
        menu.addAction("Settings…", #selector(openSettings), target: self, key: ",")
        menu.addItem(themeMenu())
        menu.addAction("Add Custom Font…", #selector(addCustomFont), target: self)
        menu.addItem(.separator())

        menu.addAction("Show Lyrics", #selector(toggleLyrics), target: self, checked: settings.lyricsVisible)
        menu.addAction("Edge Lighting", #selector(toggleLights), target: self, checked: settings.lights.enabled)
        menu.addAction("Corner Mode  (⌃⌥L)", #selector(toggleCorner), target: self, checked: settings.corner.enabled)
        menu.addItem(cornerPositionMenu())
        menu.addAction("Match Album Colors", #selector(toggleArtworkColors), target: self, checked: settings.useArtworkColors)

        let sync = NSMenuItem(title: String(format: "Sync Offset (%+.1fs)", settings.overlay.latencyOffset), action: nil, keyEquivalent: "")
        let syncMenu = NSMenu()
        for (label, delta) in [("Lyrics Earlier (−0.1s)", -0.1), ("Lyrics Later (+0.1s)", 0.1)] {
            let item = syncMenu.addAction(label, #selector(nudgeOffset(_:)), target: self)
            item.representedObject = delta
        }
        syncMenu.addItem(.separator())
        syncMenu.addAction("Reset", #selector(resetOffset), target: self)
        sync.submenu = syncMenu
        menu.addItem(sync)

        menu.addItem(.separator())
        menu.addAction("Quit Lyra", #selector(quit), target: self, key: "q")
    }

    private func cornerPositionMenu() -> NSMenuItem {
        let parent = NSMenuItem(title: "Corner Position", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for corner in ScreenCorner.allCases {
            let item = sub.addAction(corner.title, #selector(setCorner(_:)), target: self,
                                     checked: settings.corner.corner == corner)
            item.representedObject = corner.rawValue
        }
        parent.submenu = sub
        return parent
    }

    private func themeMenu() -> NSMenuItem {
        let parent = NSMenuItem(title: "Theme", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        let active = model.activeThemeID
        for theme in model.themes {
            let item = sub.addAction(theme.name, #selector(applyTheme(_:)), target: self, checked: theme.id == active)
            item.representedObject = theme.id
        }
        if active == nil {
            sub.addItem(.separator())
            sub.addItem(disabled: "Custom look")
        }
        parent.submenu = sub
        return parent
    }

    private func lyricsStatusText(_ state: SessionState) -> String {
        switch state.status {
        case .idle: return "Play something in Spotify or Music"
        case .loading: return "Finding lyrics…"
        case .ready: return state.document?.hasWordTiming == true ? "Synced lyrics (word timing)" : "Synced lyrics (estimated word timing)"
        case .unavailable: return "No synced lyrics for this track"
        }
    }

    private func audioStatusText() -> String {
        guard settings.lights.enabled else { return "Lighting off" }
        switch capture.state {
        case .capturing: return "Audio: listening"
        case .starting: return "Audio: starting…"
        case .stopped: return "Audio: starts when music plays"
        case .permissionDenied: return "Audio: permission needed (lights use a gentle glow)"
        case .noSignal: return "Audio: no sound arriving (nothing playing, or System Audio Recording not allowed)"
        case .failed(let reason): return "Audio: \(reason)"
        }
    }

    // MARK: - Actions

    /// Enters or leaves native full screen for the player, opening it first if needed.
    public func toggleFullScreen() { toggleFullScreenPlayer() }

    @objc private func openSettings() { showSettings() }
    @objc private func openPlayer() { showPlayer() }

    @objc private func toggleFullScreenPlayer() {
        showPlayer()
        playerWindow?.toggleFullScreen()
    }

    @objc private func applyTheme(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let theme = model.themes.first(where: { $0.id == id }) else { return }
        model.apply(theme)
    }

    @objc private func toggleLyrics() { settings.lyricsVisible.toggle() }
    @objc private func toggleLights() { settings.lights.enabled.toggle() }
    @objc private func toggleCorner() { settings.corner.enabled.toggle() }

    /// Choosing a corner also turns corner mode on: picking where it goes means you want it.
    @objc private func setCorner(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let corner = ScreenCorner(rawValue: raw) else { return }
        var s = settings
        s.corner.corner = corner
        s.corner.enabled = true
        settings = s
    }

    /// For demos and screenshots: shows the Cinematic lyric style with the film look on, in the player,
    /// without ever saving.
    public func showCinematicDemo() {
        persistSettings = false
        var s = settings
        s.styleID = "cinematic"
        s.player.cinema.enabled = true
        s.player.openAtLaunch = true
        settings = s
        showPlayer()
    }

    /// For overlay debugging: forces the overlay on with a fixed invented line, in full-screen or corner
    /// layout, without music and without ever saving.
    public func showOverlayDemo(corner: Bool, screenCorner: ScreenCorner = .bottomRight) {
        persistSettings = false
        let line = "Overlay check line"
        let next = "Second invented line"
        func mk(_ t: String, _ a: TimeInterval, _ b: TimeInterval) -> LyricLine {
            LyricLine(start: a, end: b, sungEnd: b, text: t, words: [LyricWord(text: t, start: a, end: b, isEstimated: true)])
        }
        demoDocument = LyricsDocument(lines: [mk(line, 0, 1000), mk(next, 1000, 2000)], isSynced: true,
                                      hasWordTiming: false, source: "demo")
        var s = settings
        s.lyricsVisible = true
        s.lights.enabled = false
        s.player.hideOverlayWhenOpen = false   // the demo overlay must show even with the player window open
        s.corner.enabled = corner
        s.corner.corner = screenCorner
        settings = s
        overlay.relayout()
        applyVisibility()
    }

    private func demoItems(_ doc: LyricsDocument, viewport: CGSize) -> [DrawItem] {
        var config = ThemeResolver.resolve(settings.overlay, palette: nil, useArtworkColors: false)
        let cornerMode = settings.corner.enabled
        if cornerMode { config = CornerOverlay.config(from: config, settings: settings.corner) }
        let position: TimeInterval = 500
        let frame = LyricsFrame(lines: doc.lines, cursor: LyricsCursor(document: doc).state(at: position), position: position)
        return LyricsPipeline.items(style: style(id: cornerMode ? "karaoke" : settings.styleID), frame: frame,
                                    viewport: viewport, config: config, measurer: measurer)
    }

    /// For demos and screenshots: turns on corner mode in `corner` without ever saving, so a
    /// temporary look can't reach the user's settings file.
    public func showCornerDemo(corner: ScreenCorner) {
        persistSettings = false
        var s = settings
        s.corner.enabled = true
        s.corner.corner = corner
        settings = s
    }

    /// One switch for both: the lyrics' glow and the edge lights follow the cover together.
    @objc private func toggleArtworkColors() {
        var s = settings
        s.useArtworkColors.toggle()
        s.lights.useArtworkColors = s.useArtworkColors
        settings = s
    }

    @objc private func nudgeOffset(_ sender: NSMenuItem) {
        guard let delta = sender.representedObject as? Double else { return }
        settings.overlay.latencyOffset = ((settings.overlay.latencyOffset + delta) * 10).rounded() / 10
    }

    @objc private func resetOffset() { settings.overlay.latencyOffset = 0 }

    /// Opens the System Settings pane for the permission the current audio backend needs.
    @objc @MainActor private func addCustomFont() {
        FontCatalog.addCustomFontsFromPanel()
    }

    @objc private func openAudioPermissions() {
        let url = capture.source == .systemTap
            ? SystemAudioCapture.privacySettingsURL
            : SystemAudioCapture.screenCapturePrivacySettingsURL
        NSWorkspace.shared.open(url)
    }

    @objc private func retryCapture() { startCapture() }

    @objc private func quit() {
        stop()
        NSApp.terminate(nil)
    }
}

private extension NSMenu {
    func addItem(disabled title: String) {
        addItem(withTitle: title, action: nil, keyEquivalent: "").isEnabled = false
    }

    @discardableResult
    func addAction(_ title: String, _ action: Selector, target: AnyObject, checked: Bool? = nil, key: String = "") -> NSMenuItem {
        let item = addItem(withTitle: title, action: action, keyEquivalent: key)
        item.target = target
        if let checked { item.state = checked ? .on : .off }
        return item
    }
}
