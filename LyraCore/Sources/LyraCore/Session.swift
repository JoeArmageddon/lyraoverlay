import Foundation

public enum LyricsStatus: Equatable, Sendable {
    case idle
    case loading
    case ready
    /// No synced lyrics exist for this track (none found, plain only, or instrumental).
    case unavailable
}

/// Everything a view needs to draw one frame. Immutable copy, safe to use off-lock.
public struct SessionState: Sendable {
    public var snapshot: PlaybackSnapshot
    public var document: LyricsDocument?
    public var cursor: LyricsCursor?
    public var status: LyricsStatus
    public var trackKey: String
    /// Colors from the current track's artwork; nil until fetched, or if there is none.
    public var palette: Palette?

    /// Lyrics clock at `date`, shifted by `offset` seconds (positive shows lyrics later).
    public func position(at date: Date = Date(), offset: TimeInterval = 0) -> TimeInterval {
        snapshot.position(at: date) - offset
    }
}

/// Glues now-playing, lyrics lookup and the cursor together behind one thread-safe object.
public final class LyricsSession: @unchecked Sendable {
    private let monitor: NowPlayingMonitor
    private let service: LyricsService
    private let artworkProvider: ArtworkProvider
    private let lock = NSLock()
    private var state = SessionState(snapshot: .idle, document: nil, cursor: nil, status: .idle, trackKey: "")
    private var palettes = PaletteCache(capacity: 50)
    private var task: Task<Void, Never>?

    /// Called on an arbitrary thread when the playing track changes.
    public var onTrackChange: (@Sendable (Track?) -> Void)?
    public var onProblem: (@Sendable (PlayerKind, ScriptError) -> Void)? {
        get { monitor.onProblem }
        set { monitor.onProblem = newValue }
    }

    public init(monitor: NowPlayingMonitor = NowPlayingMonitor(),
                service: LyricsService = LyricsService(),
                artworkProvider: ArtworkProvider = PlayerArtworkProvider()) {
        self.monitor = monitor
        self.service = service
        self.artworkProvider = artworkProvider
    }

    public var current: SessionState { lock.withLock { state } }

    public func start() {
        guard task == nil else { return }
        let stream = monitor.start()
        task = Task { [weak self] in
            for await snapshot in stream {
                guard let self else { return }
                self.apply(snapshot)
            }
        }
    }

    /// Moves the lyrics clock right away after the user seeks, instead of waiting for the next
    /// poll of the player (up to a second), so the words jump with the scrub.
    public func noteSeek(to position: TimeInterval) {
        lock.withLock {
            guard state.snapshot.track != nil else { return }
            state.snapshot.position = max(0, position)
            state.snapshot.capturedAt = Date()
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
        monitor.stop()
    }

    // MARK: - Internals

    private static func key(for track: Track?) -> String {
        track.map { "\($0.player.rawValue)|\($0.id)|\($0.title)|\($0.artist)" } ?? ""
    }

    private func apply(_ snapshot: PlaybackSnapshot) {
        let key = Self.key(for: snapshot.track)
        var needsPalette = false
        let changed: Bool = lock.withLock {
            state.snapshot = snapshot
            guard key != state.trackKey else { return false }
            state.trackKey = key
            state.document = nil
            state.cursor = nil
            state.status = snapshot.track == nil ? .idle : .loading
            // A replayed track gets its colors back instantly.
            state.palette = palettes.palette(for: key)
            needsPalette = snapshot.track != nil && state.palette == nil
            return true
        }
        guard changed else { return }
        onTrackChange?(snapshot.track)
        guard let track = snapshot.track else { return }

        Task { [service, weak self] in
            let doc = await service.lyrics(for: TrackQuery(track: track))
            self?.setDocument(doc, forTrackKey: key)
        }
        if needsPalette {
            // Independent of the lyrics lookup: a missing or unreadable cover only means no colors.
            Task { [artworkProvider, weak self] in
                guard let image = await artworkProvider.artwork(for: track),
                      let palette = PaletteExtractor.extract(from: image) else { return }
                self?.setPalette(palette, forTrackKey: key)
            }
        }
    }

    private func setPalette(_ palette: Palette, forTrackKey key: String) {
        lock.withLock {
            palettes.store(palette, for: key)
            // The track may have changed while the artwork loaded.
            guard key == state.trackKey else { return }
            state.palette = palette
        }
    }

    private func setDocument(_ doc: LyricsDocument?, forTrackKey key: String) {
        lock.withLock {
            // The track may have changed while the lookup ran.
            guard key == state.trackKey else { return }
            state.document = doc
            if let doc, doc.isSynced, !doc.lines.isEmpty {
                state.cursor = LyricsCursor(document: doc)
                state.status = .ready
            } else {
                state.cursor = nil
                state.status = .unavailable
            }
        }
    }
}
