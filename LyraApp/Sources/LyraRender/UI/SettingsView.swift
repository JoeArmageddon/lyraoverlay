import SwiftUI
import UniformTypeIdentifiers
import LyraCore

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    let preview: PreviewRenderer
    @State private var tab: Tab

    enum Tab: String, Hashable { case themes, lyrics, lights, player, general }

    init(model: SettingsModel, preview: PreviewRenderer, initialTab: Tab = .themes) {
        self.model = model
        self.preview = preview
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(spacing: 0) {
            PreviewPane(model: model, preview: preview)
            Divider()
            TabView(selection: $tab) {
                ThemesTab(model: model).tabItem { Label("Themes", systemImage: "paintpalette") }.tag(Tab.themes)
                LyricsTab(model: model).tabItem { Label("Lyrics", systemImage: "textformat") }.tag(Tab.lyrics)
                LightsTab(model: model).tabItem { Label("Lights", systemImage: "light.max") }.tag(Tab.lights)
                PlayerTab(model: model).tabItem { Label("Player", systemImage: "rectangle.on.rectangle") }.tag(Tab.player)
                GeneralTab(model: model).tabItem { Label("General", systemImage: "gearshape") }.tag(Tab.general)
            }
        }
        .frame(minWidth: 620, minHeight: 640)
        .alert("Lyra", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("OK") { model.message = nil }
        } message: {
            Text(model.message ?? "")
        }
    }
}

// MARK: - Live preview

private struct PreviewPane: View {
    @ObservedObject var model: SettingsModel
    let preview: PreviewRenderer
    @State private var onLight = false

    var body: some View {
        (onLight ? Color(white: 0.92) : Color(white: 0.09))
            .overlay {
                TimelineView(.periodic(from: .now, by: 1.0 / 15.0)) { context in
                    // Rendered at a typical laptop screen width and scaled down, so line wrapping and
                    // the proportions of text and lights match what the real overlay will do.
                    if let image = preview.image(settings: model.settings, time: context.date.timeIntervalSinceReferenceDate,
                                                 size: CGSize(width: 1440, height: 540), scale: 1) {
                        Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)   // centered, not pushed to a corner
            }
            .overlay(alignment: .topTrailing) {
                Toggle("Light background", isOn: $onLight).toggleStyle(.checkbox).font(.caption).padding(8)
            }
            .frame(height: 230)
    }
}

// MARK: - Themes

private struct ThemesTab: View {
    @ObservedObject var model: SettingsModel
    @State private var naming = false
    @State private var newName = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    ForEach(model.themes) { theme in
                        ThemeCard(theme: theme, active: theme.id == model.activeThemeID)
                            .onTapGesture { model.apply(theme) }
                            .contextMenu {
                                Button("Export…") { exportTheme(theme) }
                                if !theme.id.hasPrefix("builtin.") {
                                    Button("Delete", role: .destructive) { model.delete(theme) }
                                }
                            }
                    }
                }
                HStack {
                    Button("Save Current Look as Theme…") { newName = ""; naming = true }
                    Button("Import Theme…") { importTheme() }
                    Spacer()
                    if model.activeThemeID == nil {
                        Text("Custom look").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("Right-click a theme to export or delete it. Themes don't include your sync offset.")
                    .font(.caption).foregroundStyle(.secondary)
                MatchTheMusicSection(model: model)
            }
            .padding(20)
        }
        .alert("Save Theme", isPresented: $naming) {
            TextField("Name", text: $newName)
            Button("Save") { model.saveCurrentAsTheme(named: newName) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saves the current style, font, colors and lighting.")
        }
    }

    private func exportTheme(_ theme: Theme) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(theme.name).json"
        if panel.runModal() == .OK, let url = panel.url { model.export(theme, to: url) }
    }

    private func importTheme() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { model.importTheme(from: url) }
    }
}

struct ThemeCard: View {
    let theme: Theme
    let active: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // The name and a sample line in the theme's own font, so the card previews the look.
            Text(theme.overlay.textCase.apply(theme.name))
                .font(themeFont(size: 22))
                .tracking(theme.overlay.font.tracking * 22)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(theme.overlay.textCase.apply("Hold on to the feeling"))
                .font(themeFont(size: 13))
                .tracking(theme.overlay.font.tracking * 13)
                .foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(styleName).font(.caption2).foregroundStyle(.tertiary)
            HStack(spacing: 4) {
                Circle().fill(Color(theme.overlay.glowColor)).frame(width: 10, height: 10)
                if theme.lights.enabled {
                    Circle().fill(Color(theme.lights.primary ?? RimGlowEffect.defaultPrimary)).frame(width: 10, height: 10)
                    Circle().fill(Color(theme.lights.secondary ?? RimGlowEffect.defaultSecondary)).frame(width: 10, height: 10)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(active ? Color.accentColor : .clear, lineWidth: 2))
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }

    private func themeFont(size: CGFloat) -> Font {
        let f = theme.overlay.font
        return FontPreview.font(f.family, size: size, weight: f.weight, italic: f.italic)
    }

    private var styleName: String {
        LyricStyles.all.first { $0.id == theme.styleID }?.name ?? "Karaoke Line"
    }
}

// MARK: - Lyrics

private struct LyricsTab: View {
    @ObservedObject var model: SettingsModel
    @State private var showFontPicker = false

    var body: some View {
        Form {
            Section("Style") {
                Picker("Style", selection: model.binding(\.styleID)) {
                    ForEach(LyricStyles.all) { Text($0.name).tag($0.id) }
                }
                if let info = LyricStyles.all.first(where: { $0.id == model.settings.styleID }) {
                    Text(info.summary).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Font") {
                HStack {
                    Text("Family")
                    Spacer()
                    // The current font shown in itself; the button opens the full picker with previews.
                    Button { showFontPicker = true } label: {
                        HStack(spacing: 6) {
                            Text(FontCatalog.displayName(for: model.settings.overlay.font.family))
                                .font(FontPreview.font(model.settings.overlay.font.family, size: 17,
                                                       weight: model.settings.overlay.font.weight,
                                                       italic: model.settings.overlay.font.italic))
                                .lineLimit(1)
                            Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .popover(isPresented: $showFontPicker, arrowEdge: .bottom) { FontPicker(model: model) }
                }
                labeled("Size", value: model.settings.overlay.font.size, format: "%.0f pt") {
                    Slider(value: model.binding(\.overlay.font.size), in: 20...120)
                }
                labeled("Weight", value: model.settings.overlay.font.weight, format: "%.2f") {
                    Slider(value: model.binding(\.overlay.font.weight), in: -0.6...0.9)
                }
                .disabled(model.settings.overlay.font.family != "System")
                if model.settings.overlay.font.family != "System" {
                    Text("Weight applies to the system font; other fonts use the weight of the face you pick.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                labeled("Letter spacing", value: model.settings.overlay.font.tracking, format: "%.2f em") {
                    Slider(value: model.binding(\.overlay.font.tracking), in: -0.05...0.3)
                }
                Toggle("Italic", isOn: model.binding(\.overlay.font.italic))
                Picker("Case", selection: model.binding(\.overlay.textCase)) {
                    ForEach(TextCase.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Button("Add Custom Font…") { importFont() }
            }

            Section("Colors") {
                Toggle("Match album colors", isOn: model.binding(\.useArtworkColors))
                ColorPicker("Sung text", selection: model.colorBinding(\.overlay.highlightColor), supportsOpacity: true)
                ColorPicker("Upcoming text", selection: model.colorBinding(\.overlay.baseColor), supportsOpacity: true)
                ColorPicker("Glow", selection: model.colorBinding(\.overlay.glowColor), supportsOpacity: false)
                Text("With album colors on, the glow and sung-text tint come from the cover; your colors apply when there is no artwork.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Effects") {
                labeled("Glow", value: Double(model.settings.overlay.glow), format: "%.2f") {
                    Slider(value: model.floatBinding(\.overlay.glow), in: 0...1.5)
                }
                labeled("Shadow", value: Double(model.settings.overlay.shadow), format: "%.2f") {
                    Slider(value: model.floatBinding(\.overlay.shadow), in: 0...1)
                }
            }

            Section("Animation") {
                Picker("Lines appear with", selection: model.binding(\.overlay.entrance)) {
                    ForEach(EntranceAnimation.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Lines leave with", selection: model.binding(\.overlay.exit)) {
                    ForEach(ExitAnimation.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                labeled("Duration", value: model.settings.overlay.entranceDuration, format: "%.2f s") {
                    Slider(value: model.binding(\.overlay.entranceDuration), in: 0.1...1.6)
                }
                labeled("Word stagger", value: model.settings.overlay.entranceStagger, format: "%.2f s") {
                    Slider(value: model.binding(\.overlay.entranceStagger), in: 0...0.25)
                }
                Text("Stagger delays each word after the one before it; it is used by Cascade.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Layout") {
                labeled("Vertical position", value: model.settings.overlay.anchorY, format: "%.2f") {
                    Slider(value: model.binding(\.overlay.anchorY), in: 0.05...0.9)
                }
                labeled("Maximum width", value: model.settings.overlay.maxWidthFraction, format: "%.2f") {
                    Slider(value: model.binding(\.overlay.maxWidthFraction), in: 0.4...0.95)
                }
                Toggle("Show the next line", isOn: model.binding(\.overlay.showNextLine))
            }

            Section("Timing") {
                labeled("Sync offset", value: model.settings.overlay.latencyOffset, format: "%+.2f s") {
                    Slider(value: model.binding(\.overlay.latencyOffset), in: -2...2, step: 0.05)
                }
                Button("Reset Offset") { model.settings.overlay.latencyOffset = 0 }
                    .disabled(model.settings.overlay.latencyOffset == 0)
                Text("Positive shows lyrics later, negative earlier. Adjust it if the words run ahead of or behind the singer.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func importFont() {
        let results = FontCatalog.addCustomFontsFromPanel()
        guard !results.isEmpty else { return }
        if let id = results.first(where: \.succeeded)?.fontID { model.settings.overlay.font.family = id }
        model.message = ImportResult.summary(results)
    }
}

// MARK: - Lights

private struct LightsTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section("Edge lighting") {
                Toggle("Enable edge lighting", isOn: model.binding(\.lights.enabled))
                labeled("Intensity", value: Double(model.settings.lights.intensity), format: "%.2f") {
                    Slider(value: model.floatBinding(\.lights.intensity), in: 0...1)
                }
                labeled("Thickness", value: model.settings.lights.thickness, format: "%.0f pt") {
                    Slider(value: model.binding(\.lights.thickness), in: 8...80)
                }
                labeled("Corner radius", value: model.settings.lights.cornerRadius, format: "%.0f pt") {
                    Slider(value: model.binding(\.lights.cornerRadius), in: 0...40)
                }
            }

            Section("Music reaction") {
                labeled("Beat reaction", value: Double(model.settings.lights.beatReactivity), format: "%.2f") {
                    Slider(value: model.floatBinding(\.lights.beatReactivity), in: 0...1)
                }
                labeled("Resting glow", value: Double(model.settings.lights.idleGlow), format: "%.2f") {
                    Slider(value: model.floatBinding(\.lights.idleGlow), in: 0...0.6)
                }
                labeled("Color drift", value: model.settings.lights.driftSpeed, format: "%.2f turns/s") {
                    Slider(value: model.binding(\.lights.driftSpeed), in: 0...0.3)
                }
                Text("Reaction needs audio access; without it the lights breathe gently.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Colors") {
                Toggle("Follow album colors", isOn: model.binding(\.lights.useArtworkColors))
                ColorPicker("Primary", selection: model.optionalColorBinding(\.lights.primary, fallback: RimGlowEffect.defaultPrimary), supportsOpacity: false)
                    .disabled(model.settings.lights.useArtworkColors)
                ColorPicker("Secondary", selection: model.optionalColorBinding(\.lights.secondary, fallback: RimGlowEffect.defaultSecondary), supportsOpacity: false)
                    .disabled(model.settings.lights.useArtworkColors)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Player

private struct PlayerTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section("Window") {
                Toggle("Open the player when Lyra starts", isOn: model.binding(\.player.openAtLaunch))
                Toggle("Keep the window on top", isOn: model.binding(\.player.keepOnTop))
                Toggle("Hide the desktop overlay while the player is open", isOn: model.binding(\.player.hideOverlayWhenOpen))
                Toggle("Keep my Mac awake while music plays", isOn: model.binding(\.player.keepAwake))
                Text("The display won't sleep while the player is open and a song is playing. Full screen works the same way.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Background") {
                Picker("Fit", selection: model.binding(\.player.fill)) {
                    ForEach(BackgroundFill.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                labeled("Darken", value: model.settings.player.dim, format: "%.2f") {
                    Slider(value: model.binding(\.player.dim), in: 0...0.85)
                }
                labeled("Blur", value: model.settings.player.blur, format: "%.0f pt") {
                    Slider(value: model.binding(\.player.blur), in: 0...40)
                }
                Text("Pick or upload an image or video with the background button in the player window.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Border") {
                Toggle("Border follows the background's colors", isOn: model.binding(\.player.borderFollowsBackground))
                Toggle("Show the border", isOn: model.binding(\.player.border.enabled))
                labeled("Intensity", value: Double(model.settings.player.border.intensity), format: "%.2f") {
                    Slider(value: model.floatBinding(\.player.border.intensity), in: 0...1)
                }
                labeled("Thickness", value: model.settings.player.border.thickness, format: "%.0f pt") {
                    Slider(value: model.binding(\.player.border.thickness), in: 8...90)
                }
                labeled("Beat reaction", value: Double(model.settings.player.border.beatReactivity), format: "%.2f") {
                    Slider(value: model.floatBinding(\.player.border.beatReactivity), in: 0...1)
                }
                labeled("Corner radius", value: model.settings.player.border.cornerRadius, format: "%.0f pt") {
                    Slider(value: model.binding(\.player.border.cornerRadius), in: 0...40)
                }
            }

            Section("Film look") {
                Toggle("Cinematic finish", isOn: model.binding(\.player.cinema.enabled))
                Text("Widescreen bars, a darkened vignette, film grain and a light streak that flares on the beat. It pairs well with the Cinematic lyric style.")
                    .font(.caption).foregroundStyle(.secondary)
                Group {
                    Picker("Letterbox", selection: model.binding(\.player.cinema.letterbox)) {
                        ForEach(LetterboxRatio.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    labeled("Vignette", value: model.settings.player.cinema.vignette, format: "%.2f") {
                        Slider(value: model.binding(\.player.cinema.vignette), in: 0...1)
                    }
                    labeled("Film grain", value: model.settings.player.cinema.grain, format: "%.2f") {
                        Slider(value: model.binding(\.player.cinema.grain), in: 0...1)
                    }
                    labeled("Light streak", value: model.settings.player.cinema.flare, format: "%.2f") {
                        Slider(value: model.binding(\.player.cinema.flare), in: 0...1)
                    }
                }
                .disabled(!model.settings.player.cinema.enabled)
            }

            Section("Lyrics and controls") {
                labeled("Lyrics size", value: model.settings.player.lyricsScale, format: "%.2fx") {
                    Slider(value: model.binding(\.player.lyricsScale), in: 0.5...2.0)
                }
                Toggle("Show the now-playing card", isOn: model.binding(\.player.showNowPlayingCard))
                Toggle("Show playback controls", isOn: model.binding(\.player.showControls))
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - General

private struct GeneralTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section("Corner mode") {
                Toggle("Show lyrics in a small corner card", isOn: model.binding(\.corner.enabled))
                Text("Instead of across the whole screen, the lyrics sit in a small caption card in one corner, clear of the menu bar and Dock. Edge lights are off in this mode. Toggle it from any app with ⌃⌥L.")
                    .font(.caption).foregroundStyle(.secondary)
                Group {
                    Picker("Corner", selection: model.binding(\.corner.corner)) {
                        ForEach(ScreenCorner.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    labeled("Text size", value: model.settings.corner.fontSize, format: "%.0f pt") {
                        Slider(value: model.binding(\.corner.fontSize), in: CornerOverlay.fontSizeRange)
                    }
                    labeled("Card width", value: model.settings.corner.width, format: "%.0f pt") {
                        Slider(value: model.binding(\.corner.width), in: CornerOverlay.widthRange)
                    }
                    labeled("Distance from the edge", value: model.settings.corner.margin, format: "%.0f pt") {
                        Slider(value: model.binding(\.corner.margin), in: CornerOverlay.marginRange)
                    }
                    Toggle("Show the next line", isOn: model.binding(\.corner.showNextLine))
                    Toggle("Dark backdrop behind the text", isOn: model.binding(\.corner.showBackdrop))
                    labeled("Backdrop opacity", value: model.settings.corner.backdropOpacity, format: "%.2f") {
                        Slider(value: model.binding(\.corner.backdropOpacity), in: 0.1...1)
                    }
                    .disabled(!model.settings.corner.showBackdrop)
                }
                .disabled(!model.settings.corner.enabled)
            }

            Section("Overlay") {
                Toggle("Show lyrics", isOn: model.binding(\.lyricsVisible))
                Toggle("Show on all displays", isOn: model.binding(\.allDisplays))
                Picker("Window level", selection: model.binding(\.level)) {
                    ForEach(OverlayLevel.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
            Section("Album art") {
                Toggle("Look up missing covers online", isOn: model.binding(\.onlineArtwork))
                Text("Streamed Apple Music tracks give no cover to other apps. With this on, Lyra asks Apple's public iTunes Search for it, which sends the artist and album name to Apple. Covers drive the colors of the lyrics, lights and now-playing card. Turn it off to keep those names on your Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("About") {
                Text("Settings are saved automatically in ~/Library/Application Support/Lyra.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Shared

/// A slider row with its name and current value.
private func labeled<Content: View>(_ title: String, value: Double, format: String, @ViewBuilder _ content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        HStack {
            Text(title)
            Spacer()
            Text(String(format: format, value)).foregroundStyle(.secondary).monospacedDigit()
        }
        content()
    }
}
