import Foundation

public enum BackgroundFill: String, Codable, CaseIterable, Sendable {
    /// Cover the whole window, cropping the edges if the aspect ratios differ.
    case fill
    /// Show the whole picture or video, with bars if the aspect ratios differ.
    case fit

    public var title: String { self == .fill ? "Fill" : "Fit" }
}

/// The aspect ratio of the black bars drawn top and bottom for a widescreen film look.
public enum LetterboxRatio: String, Codable, CaseIterable, Sendable {
    case off
    case cinemascope   // 2.39:1
    case flat          // 1.85:1
    case wide          // 2.00:1

    public var title: String {
        switch self {
        case .off: return "None"
        case .cinemascope: return "2.39:1 CinemaScope"
        case .flat: return "1.85:1 Flat"
        case .wide: return "2.00:1 Univisium"
        }
    }

    /// Width divided by height of the picture area; nil when there are no bars.
    public var aspect: Double? {
        switch self {
        case .off: return nil
        case .cinemascope: return 2.39
        case .flat: return 1.85
        case .wide: return 2.0
        }
    }
}

/// Film-look finishing for the player: bars, vignette, grain and an anamorphic streak on beats.
public struct CinemaSettings: Equatable, Codable, Sendable {
    public var enabled = false
    public var letterbox = LetterboxRatio.cinemascope
    /// 0...1 darkening toward the corners.
    public var vignette = 0.45
    /// 0...1 animated film grain.
    public var grain = 0.18
    /// 0...1 horizontal light streak that flares on beats and emphasized words.
    public var flare = 0.5

    public init() {}

    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = c.get(.enabled, enabled)
        letterbox = c.get(.letterbox, letterbox)
        vignette = c.get(.vignette, vignette)
        grain = c.get(.grain, grain)
        flare = c.get(.flare, flare)
    }
}

/// Everything about the player window that the user can change.
public struct PlayerSettings: Equatable, Codable, Sendable {
    /// A `BackgroundLibrary` item id; built-ins start with "builtin.".
    public var backgroundID = "builtin.midnight"
    /// 0...0.85: how much the background is darkened so lyrics stay readable.
    public var dim = 0.35
    /// 0...40 points of Gaussian blur on the background.
    public var blur = 0.0
    public var fill = BackgroundFill.fill
    /// The window's glowing border takes its gradient from the background's colors.
    public var borderFollowsBackground = true
    public var border: LightConfig = {
        var c = LightConfig()
        c.thickness = 36
        c.intensity = 0.95
        c.cornerRadius = 10
        return c
    }()
    /// Keep the Mac (and display) awake while the player is open and music is playing.
    public var keepAwake = true
    public var keepOnTop = false
    public var showNowPlayingCard = true
    public var showControls = true
    public var openAtLaunch = true
    /// Hide the desktop overlay while the player window is open, so lyrics aren't drawn twice.
    public var hideOverlayWhenOpen = true
    /// Multiplier on the lyric text size, on top of scaling with the window width.
    public var lyricsScale = 1.0
    /// Bars, vignette, grain and flare for a film look.
    public var cinema = CinemaSettings()

    public init() {}

    /// Tolerant: missing or malformed keys keep their defaults.
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        backgroundID = c.get(.backgroundID, backgroundID)
        dim = c.get(.dim, dim)
        blur = c.get(.blur, blur)
        fill = c.get(.fill, fill)
        borderFollowsBackground = c.get(.borderFollowsBackground, borderFollowsBackground)
        border = c.get(.border, border)
        keepAwake = c.get(.keepAwake, keepAwake)
        keepOnTop = c.get(.keepOnTop, keepOnTop)
        showNowPlayingCard = c.get(.showNowPlayingCard, showNowPlayingCard)
        showControls = c.get(.showControls, showControls)
        openAtLaunch = c.get(.openAtLaunch, openAtLaunch)
        hideOverlayWhenOpen = c.get(.hideOverlayWhenOpen, hideOverlayWhenOpen)
        lyricsScale = c.get(.lyricsScale, lyricsScale)
        cinema = c.get(.cinema, cinema)
    }
}
