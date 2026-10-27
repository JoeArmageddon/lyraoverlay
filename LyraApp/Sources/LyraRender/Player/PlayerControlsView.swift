import SwiftUI
import UniformTypeIdentifiers
import LyraCore

/// What the controls overlay shows; the window controller updates it twice a second.
final class PlayerUIState: ObservableObject {
    @Published var title = ""
    @Published var artist = ""
    @Published var art: NSImage?
    @Published var isPlaying = false
    /// Shown while there are no synced lyrics to draw (nothing playing, looking up, none exist).
    @Published var status: String?
    @Published var controlsVisible = true
    @Published var pickerShown = false
    @Published var isFullScreen = false

    var hasTrack: Bool { !title.isEmpty }
}

struct PlayerActions {
    var playPause: () -> Void
    var next: () -> Void
    var previous: () -> Void
    var toggleFullScreen: () -> Void
}

/// The transparent layer over the lyrics: now-playing card, transport buttons and the background
/// picker. Everything but the status line fades out when the pointer is idle.
struct PlayerControlsView: View {
    @ObservedObject var ui: PlayerUIState
    @ObservedObject var model: SettingsModel
    @ObservedObject var backgrounds: BackgroundLibraryModel
    let session: LyricsSession
    let actions: PlayerActions

    private var player: PlayerSettings { model.settings.player }

    var body: some View {
        ZStack {
            VStack {
                HStack {
                    if player.showNowPlayingCard, ui.hasTrack { NowPlayingCard(ui: ui) }
                    Spacer()
                }
                .padding(.top, 44)   // clear of the traffic lights
                .padding(.horizontal, 20)
                Spacer()
                if player.showControls {
                    VStack(spacing: 12) {
                        SeekBarView(snapshot: { session.current.snapshot }, onSeek: { seconds, track in
                            // The lyrics jump now; the player follows a moment later.
                            session.noteSeek(to: seconds)
                            Task { _ = await PlayerControl.seek(to: seconds, player: track.player) }
                        })
                            .frame(maxWidth: 560)
                            .padding(.horizontal, 28)
                        transportBar
                    }
                    .padding(.bottom, 24)
                }
            }
            .opacity(ui.controlsVisible || ui.pickerShown ? 1 : 0)
            .allowsHitTesting(ui.controlsVisible || ui.pickerShown)
            .animation(.easeInOut(duration: 0.25), value: ui.controlsVisible)

            if let status = ui.status {
                VStack {
                    Spacer()
                    Text(status)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(.black.opacity(0.35), in: Capsule())
                        .padding(.bottom, player.showControls ? 140 : 28)
                }
                .allowsHitTesting(false)
            }
        }
        .environment(\.colorScheme, .dark)
    }

    private var transportBar: some View {
        HStack(spacing: 18) {
            button("backward.fill", help: "Previous", action: actions.previous)
            button(ui.isPlaying ? "pause.fill" : "play.fill", help: ui.isPlaying ? "Pause" : "Play", size: 22, action: actions.playPause)
            button("forward.fill", help: "Next", action: actions.next)
            Divider().frame(height: 18)
            button("photo.on.rectangle", help: "Background") { ui.pickerShown.toggle() }
                .popover(isPresented: $ui.pickerShown, arrowEdge: .top) {
                    BackgroundPickerView(model: model, backgrounds: backgrounds)
                }
            button(ui.isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                   help: ui.isFullScreen ? "Exit Full Screen" : "Full Screen", action: actions.toggleFullScreen)
        }
        .padding(.horizontal, 22).padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func button(_ symbol: String, help: String, size: CGFloat = 16, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size)).frame(width: 28, height: 28).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct NowPlayingCard: View {
    @ObservedObject var ui: PlayerUIState

    /// Width of the longer of title and artist at their display sizes, capped so a long title is cut with "…".
    private var textWidth: CGFloat {
        let title = (ui.title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold)]).width
        let artist = (ui.artist as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11)]).width
        return min(260, ceil(max(title, artist)) + 6)
    }

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let art = ui.art {
                    Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Rectangle().fill(.white.opacity(0.12)).overlay(Image(systemName: "music.note").foregroundStyle(.white.opacity(0.6)))
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(ui.title).font(.headline).lineLimit(1)
                Text(ui.artist).font(.subheadline).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
            }
            // As wide as the text needs, up to a limit. (`frame(maxWidth:)` alone would stretch to the limit.)
            .frame(width: textWidth, alignment: .leading)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Background picker

struct BackgroundPickerView: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var backgrounds: BackgroundLibraryModel

    private var selectedID: String { model.settings.player.backgroundID }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Background").font(.headline)

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) {
                    ForEach(backgrounds.items) { item in
                        Thumbnail(item: item, image: backgrounds.thumbnail(for: item), selected: item.id == selectedID)
                            .onTapGesture { model.settings.player.backgroundID = item.id }
                            .contextMenu {
                                if !item.isBuiltIn { Button("Delete", role: .destructive) { backgrounds.delete(item) } }
                            }
                    }
                }
                .padding(2)
            }
            .frame(height: 190)

            HStack {
                Button("Add Image or Video…") { chooseFiles() }
                if backgrounds.isImporting { ProgressView().controlSize(.small) }
            }
            if let message = backgrounds.message {
                Text(message).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }

            Divider()
            slider("Dim", value: model.binding(\.player.dim), range: 0...0.85, format: "%.0f%%", scale: 100)
            slider("Blur", value: model.binding(\.player.blur), range: 0...40, format: "%.0f pt", scale: 1)
            Picker("Fit", selection: model.binding(\.player.fill)) {
                ForEach(BackgroundFill.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Toggle("Border follows the background's colors", isOn: model.binding(\.player.borderFollowsBackground))
            Text("You can also drop images and videos onto the window.").font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 400)
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, format: String, scale: Double) -> some View {
        HStack {
            Text(title).frame(width: 44, alignment: .leading)
            Slider(value: value, in: range)
            Text(String(format: format, value.wrappedValue * scale)).monospacedDigit().foregroundStyle(.secondary).frame(width: 52, alignment: .trailing)
        }
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        let extensions = BackgroundLibrary.imageExtensions.union(BackgroundLibrary.videoExtensions)
        panel.allowedContentTypes = extensions.compactMap { UTType(filenameExtension: $0) }
        panel.message = "Choose images or videos to use as the player background."
        if panel.runModal() == .OK { backgrounds.importFiles(panel.urls) }
    }
}

private struct Thumbnail: View {
    let item: BackgroundItem
    let image: NSImage?
    let selected: Bool

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            fill
            if item.kind == .video {
                Image(systemName: "play.fill").font(.caption2).padding(4)
                    .background(.black.opacity(0.5), in: Circle()).padding(4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
            Text(item.name).font(.caption2).lineLimit(1)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.black.opacity(0.45))
        }
        .frame(height: 66)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Color.accentColor : .clear, lineWidth: 2.5))
        .contentShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder private var fill: some View {
        if item.kind == .gradient {
            LinearGradient(colors: item.stops.map { Color($0) }, startPoint: .topLeading, endPoint: .bottomTrailing)
        } else if let image {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
        } else {
            Rectangle().fill(.gray.opacity(0.3))
        }
    }
}
