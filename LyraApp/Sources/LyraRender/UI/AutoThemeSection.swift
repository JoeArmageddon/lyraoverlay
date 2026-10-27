import SwiftUI
import LyraCore

/// What song-aware theming is doing right now, for the settings window to show. The app controller
/// owns the engine and calls `update` / `clear`; the view only reads.
public final class AutoThemeStatus: ObservableObject {
    /// The one the app controller and the settings window share.
    public static let shared = AutoThemeStatus()

    @Published public var mood: Mood?
    @Published public var themeName: String?
    /// What was looked at: "Rock · 128 BPM".
    @Published public var reason: String = ""

    public init(mood: Mood? = nil, themeName: String? = nil, reason: String = "") {
        self.mood = mood
        self.themeName = themeName
        self.reason = reason
    }

    /// Shows a decision the engine just made.
    public func update(_ decision: ThemeDecision, themeName: String) {
        mood = decision.mood
        self.themeName = themeName
        reason = decision.reason
    }

    public func clear() {
        mood = nil
        themeName = nil
        reason = ""
    }

    /// "Looking at: Rock · 128 BPM → Energetic → Pulse".
    public var line: String {
        guard let mood else { return "Waiting for a song to read." }
        var parts = ["Looking at: " + (reason.isEmpty ? "the song" : reason), mood.title]
        if let themeName { parts.append(themeName) }
        return parts.joined(separator: " → ")
    }
}

/// The "Match the music" block at the bottom of the Themes tab.
struct MatchTheMusicSection: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var status: AutoThemeStatus
    @State private var showFavorites = false

    init(model: SettingsModel, status: AutoThemeStatus = .shared) {
        self.model = model
        self.status = status
    }

    private var enabled: Bool { model.settings.autoTheme.enabled }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Text("Match the music").font(.headline)
            Toggle("Switch themes to fit each song", isOn: model.binding(\.autoTheme.enabled))
            Text("Lyra reads the song's genre, its cover art and, once about 12 seconds have played, how it sounds, then picks a theme for the mood. Audio analysis needs audio permission; without it only the genre and the cover are used. Choosing a theme yourself pauses this for that song.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 18) {
                    Toggle("Genre", isOn: model.binding(\.autoTheme.useGenre))
                    Toggle("Audio", isOn: model.binding(\.autoTheme.useAudio))
                    Toggle("Cover art", isOn: model.binding(\.autoTheme.useCover))
                    Spacer()
                }
                .toggleStyle(.checkbox)

                HStack(spacing: 6) {
                    Image(systemName: "waveform").foregroundStyle(.secondary)
                    Text(enabled ? status.line : "Off: themes only change when you choose one.")
                        .font(.callout).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))

                Text("Which theme for which mood").font(.subheadline.weight(.semibold)).padding(.top, 2)
                moodList

                DisclosureGroup(isExpanded: $showFavorites) {
                    favorites.padding(.top, 6)
                } label: {
                    let n = model.settings.autoTheme.onlyThemeIDs.count
                    Text(n == 0 ? "Only use favorite themes" : "Only use favorite themes (\(n) chosen)")
                        .font(.callout)
                }
            }
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.75)
        }
    }

    // MARK: Mood list

    private var moodList: some View {
        VStack(spacing: 0) {
            ForEach(Array(Mood.selectable.enumerated()), id: \.element) { index, mood in
                if index > 0 { Divider().padding(.leading, 10) }
                MoodRow(mood: mood, themes: model.themes, selection: themeBinding(for: mood))
            }
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.25)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary, lineWidth: 1))
    }

    private func themeBinding(for mood: Mood) -> Binding<String> {
        Binding(
            get: { model.settings.autoTheme.moodThemeIDs[mood.rawValue] ?? "" },
            set: { id in
                var map = model.settings.autoTheme.moodThemeIDs
                if id.isEmpty { map.removeValue(forKey: mood.rawValue) } else { map[mood.rawValue] = id }
                model.settings.autoTheme.moodThemeIDs = map
            })
    }

    // MARK: Favorites

    private var favorites: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("When any are ticked, Lyra only picks from these. Your choices in the list above still win.")
                .font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), alignment: .leading)], alignment: .leading, spacing: 4) {
                ForEach(model.themes) { theme in
                    Toggle(theme.name, isOn: favoriteBinding(theme.id))
                        .toggleStyle(.checkbox).font(.caption).lineLimit(1)
                }
            }
            if !model.settings.autoTheme.onlyThemeIDs.isEmpty {
                Button("Clear favorites") { model.settings.autoTheme.onlyThemeIDs = [] }.controlSize(.small)
            }
        }
    }

    private func favoriteBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { model.settings.autoTheme.onlyThemeIDs.contains(id) },
            set: { on in
                var ids = model.settings.autoTheme.onlyThemeIDs
                ids.removeAll { $0 == id }
                if on { ids.append(id) }
                model.settings.autoTheme.onlyThemeIDs = ids
            })
    }
}

struct MoodRow: View {
    let mood: Mood
    let themes: [Theme]
    @Binding var selection: String

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(mood.title).font(.callout.weight(.medium))
                Text(mood.summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Picker("", selection: $selection) {
                Text("Automatic").tag("")
                Divider()
                ForEach(themes) { Text($0.name).tag($0.id) }
            }
            .labelsHidden()
            .frame(width: 150)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
    }
}
