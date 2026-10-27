import AppKit
import LyraCore

public enum OverlayLevel: String, Codable, CaseIterable, Sendable {
    /// Above the wallpaper and desktop icons, below every normal window.
    case desktop
    /// Above normal windows, like a floating panel.
    case floating
    /// Above everything, including full-screen apps.
    case aboveEverything

    public var title: String {
        switch self {
        case .desktop: return "Desktop (behind windows)"
        case .floating: return "Floating (above windows)"
        case .aboveEverything: return "Above everything"
        }
    }

    var windowLevel: NSWindow.Level {
        switch self {
        case .desktop: return NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        case .floating: return .floating
        case .aboveEverything: return .screenSaver
        }
    }
}

/// Borderless, transparent, click-through window: the whole screen, or a small card in corner mode.
///
/// It is an `NSPanel` created with `.nonactivatingPanel`, not a plain `NSWindow`. Measured on this Mac
/// (see the report in OverlayWindowTests): with the app in `.regular` activation policy, a plain
/// NSWindow with `.canJoinAllSpaces`/`.fullScreenAuxiliary` is never placed in another app's native
/// full-screen Space at any level (floating, screenSaver, shielding, assistive), while a non-activating
/// panel is, at every level. With `.accessory` both work, so the Dock icon can stay.
final class OverlayWindow: NSPanel {
    static let collectionBehavior: NSWindow.CollectionBehavior =
        [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

    init(frame: NSRect, level: NSWindow.Level, content: NSView) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        // NSPanel hides itself when the app deactivates by default; the overlay must stay up.
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isFloatingPanel = false   // the level is set explicitly below
        self.level = level
        collectionBehavior = Self.collectionBehavior
        contentView = content
        setFrame(frame, display: false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// One overlay window per screen, rebuilt when displays are added, removed or rearranged.
public final class OverlayManager {
    private let renderer: MetalRenderer
    private let itemsProvider: (CGSize) -> [DrawItem]
    private let lightProvider: (CGSize) -> LightParams?
    private var windows: [(window: OverlayWindow, view: LyricsMetalView, screen: NSScreen)] = []
    private var observer: NSObjectProtocol?
    private var active = false

    /// The window frame for a screen, in AppKit screen coordinates. nil (the default) covers the whole
    /// screen; corner mode returns a small card. Call `relayout()` after anything it depends on changes.
    public var frameProvider: ((NSScreen) -> NSRect)?
    /// A backdrop panel drawn behind the lyrics (corner mode), in view points.
    public var panelProvider: (CGSize) -> PanelParams? = { _ in nil } {
        didSet { windows.forEach { $0.view.panelProvider = panelProvider } }
    }

    public var level: OverlayLevel = .floating { didSet { windows.forEach { $0.window.level = level.windowLevel } } }
    public var allDisplays = true { didSet { if oldValue != allDisplays { rebuild() } } }
    public var isVisible = true { didSet { applyVisibility() } }

    public init(renderer: MetalRenderer,
                itemsProvider: @escaping (CGSize) -> [DrawItem],
                lightProvider: @escaping (CGSize) -> LightParams?) {
        self.renderer = renderer
        self.itemsProvider = itemsProvider
        self.lightProvider = lightProvider
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.rebuild() }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    public func rebuild() {
        windows.forEach { $0.window.orderOut(nil) }
        windows.removeAll()

        let screens = allDisplays ? NSScreen.screens : Array(NSScreen.screens.prefix(1))   // first is the primary
        for screen in screens {
            let frame = windowFrame(for: screen)
            let view = LyricsMetalView(frame: NSRect(origin: .zero, size: frame.size), renderer: renderer)
            view.itemsProvider = itemsProvider
            view.lightProvider = lightProvider
            view.panelProvider = panelProvider
            let window = OverlayWindow(frame: frame, level: level.windowLevel, content: view)
            windows.append((window, view, screen))
        }
        applyVisibility()
        windows.forEach { $0.view.setActive(false) }
        if active { windows.forEach { $0.view.setActive(true) } }
    }

    /// The overlay windows, for tests.
    var overlayWindows: [NSWindow] { windows.map { $0.window } }
    /// The current frame of every overlay window, for tests.
    var windowFrames: [NSRect] { windows.map { $0.window.frame } }
    /// Identity of the windows, so a test can tell "moved" from "recreated".
    var windowIdentities: [ObjectIdentifier] { windows.map { ObjectIdentifier($0.window) } }

    /// Moves and resizes the existing windows to the frames `frameProvider` gives now, without
    /// recreating them, so switching to corner mode or dragging a size slider is cheap.
    public func relayout() {
        for entry in windows {
            let frame = windowFrame(for: entry.screen)
            if entry.window.frame != frame { entry.window.setFrame(frame, display: true) }
        }
    }

    private func windowFrame(for screen: NSScreen) -> NSRect {
        frameProvider?(screen) ?? screen.frame
    }

    /// Whether lyrics should currently be drawn (playing, with synced lyrics).
    public func setActive(_ value: Bool) {
        active = value
        windows.forEach { $0.view.setActive(value && isVisible) }
    }

    private func applyVisibility() {
        for (window, view, _) in windows {
            if isVisible { window.orderFrontRegardless() } else { window.orderOut(nil) }
            view.setActive(active && isVisible)
        }
    }
}
