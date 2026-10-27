import Foundation
import LyraCore

/// Everything the user can tweak, persisted as one JSON file.
public struct AppSettings: Equatable, Codable, Sendable {
    public var overlay = OverlayConfig()
    public var lights = LightConfig()
    /// The standalone player window (backgrounds, full screen, keep-awake).
    public var player = PlayerSettings()
    /// Lyrics in a small card in one corner of the screen, instead of across the whole display.
    public var corner = CornerOverlaySettings()
    /// A `LyricStyles` id; unknown ids fall back to the default style.
    public var styleID = "karaoke"
    public var level = OverlayLevel.floating
    public var allDisplays = true
    public var lyricsVisible = true
    /// Tint the lyrics' glow and highlight from the album art.
    public var useArtworkColors = true
    /// When the player can't supply a cover (streamed Apple Music tracks), look it up on Apple's
    /// public iTunes Search service. This sends the artist and album name there.
    public var onlineArtwork = true
    /// Song-aware theming: restyle to match the mood of what is playing. Off by default.
    public var autoTheme = AutoThemeSettings()

    public init() {}

    /// Tolerant: a settings file from an older version, or one edited by hand, still loads.
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        overlay = c.get(.overlay, overlay)
        lights = c.get(.lights, lights)
        player = c.get(.player, player)
        corner = c.get(.corner, corner)
        styleID = c.get(.styleID, styleID)
        level = c.get(.level, level)
        allDisplays = c.get(.allDisplays, allDisplays)
        lyricsVisible = c.get(.lyricsVisible, lyricsVisible)
        useArtworkColors = c.get(.useArtworkColors, useArtworkColors)
        onlineArtwork = c.get(.onlineArtwork, onlineArtwork)
        autoTheme = c.get(.autoTheme, autoTheme)
    }
}

public struct SettingsStore {
    public let url: URL

    public init(url: URL? = nil) {
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lyra/settings.json")
    }

    /// Defaults when the file is missing or unreadable, so a corrupt file never blocks launch.
    public func load() -> AppSettings {
        guard let data = try? Data(contentsOf: url),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else { return AppSettings() }
        return settings
    }

    public func save(_ settings: AppSettings) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(settings).write(to: url, options: .atomic)
        } catch {
            NSLog("Lyra: could not save settings: \(error)")
        }
    }
}
