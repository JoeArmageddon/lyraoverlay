import Foundation
import LyraCore

/// The live, observable copy of the user's settings. The settings window edits it, the overlay
/// reads it every frame, and `onChange` is where the app persists and re-applies what needs it.
public final class SettingsModel: ObservableObject {
    @Published public var settings: AppSettings {
        didSet { if settings != oldValue { onChange?(settings) } }
    }
    @Published public private(set) var themes: [Theme]
    /// A short message for the UI to show (import errors and the like); the view clears it.
    @Published public var message: String?

    public var onChange: ((AppSettings) -> Void)?
    private let themeStore: ThemeStore

    public init(settings: AppSettings, themeStore: ThemeStore = ThemeStore()) {
        self.settings = settings
        self.themeStore = themeStore
        self.themes = themeStore.all()
    }

    // MARK: - Themes

    /// The theme the current settings exactly match, ignoring sync offset; nil means "custom".
    public var activeThemeID: String? {
        themes.first {
            $0.matches(styleID: settings.styleID, overlay: settings.overlay, lights: settings.lights, useArtworkColors: settings.useArtworkColors)
        }?.id
    }

    public func apply(_ theme: Theme) {
        var s = settings
        s.overlay = theme.overlay(preservingSyncFrom: s.overlay)
        s.lights = theme.lights
        s.styleID = theme.styleID
        s.useArtworkColors = theme.useArtworkColors
        settings = s
    }

    public func saveCurrentAsTheme(named name: String) {
        let theme = Theme(id: "", name: name, styleID: settings.styleID, overlay: settings.overlay,
                          lights: settings.lights, useArtworkColors: settings.useArtworkColors)
        do {
            try themeStore.save(theme)
            reloadThemes()
        } catch {
            message = "Could not save the theme: \(error.localizedDescription)"
        }
    }

    public func delete(_ theme: Theme) {
        guard !theme.id.hasPrefix("builtin.") else { return }
        themeStore.delete(id: theme.id)
        reloadThemes()
    }

    public func importTheme(from url: URL) {
        do {
            let theme = try themeStore.importTheme(from: url)
            reloadThemes()
            message = "Imported “\(theme.name)”."
        } catch {
            message = error.localizedDescription
        }
    }

    public func export(_ theme: Theme, to url: URL) {
        do {
            try themeStore.export(theme, to: url)
            message = "Exported “\(theme.name)”."
        } catch {
            message = "Could not export the theme: \(error.localizedDescription)"
        }
    }

    public func reloadThemes() { themes = themeStore.all() }
}
