import Foundation

/// Watches Spotify and Apple Music and publishes one `PlaybackSnapshot` stream.
///
/// Polls every second while something plays (every two when idle) and also
/// polls immediately when a player posts its change notification, so track
/// changes and seeks show up without waiting for the next tick.
public final class NowPlayingMonitor: @unchecked Sendable {
    private let sources: [PlayerSource]
    private let poller: Poller
    private var task: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    /// Called once per distinct failure when a running player can't be read,
    /// for example `.notAuthorized` when Automation permission is missing.
    public var onProblem: (@Sendable (PlayerKind, ScriptError) -> Void)?

    public init(sources: [PlayerSource] = [ScriptedPlayerSource.spotify, ScriptedPlayerSource.appleMusic]) {
        self.sources = sources
        self.poller = Poller(sources: sources)
    }

    public func start() -> AsyncStream<PlaybackSnapshot> {
        AsyncStream { continuation in
            let emit: @Sendable () async -> PlaybackSnapshot = { [poller, weak self] in
                let (snapshot, problems) = await poller.poll()
                for (kind, error) in problems { self?.onProblem?(kind, error) }
                continuation.yield(snapshot)
                return snapshot
            }

            for source in sources {
                guard let name = source.changeNotification else { continue }
                let token = DistributedNotificationCenter.default().addObserver(
                    forName: .init(name), object: nil, queue: nil
                ) { _ in Task { _ = await emit() } }
                observers.append(token)
            }

            task = Task {
                while !Task.isCancelled {
                    let snapshot = await emit()
                    try? await Task.sleep(for: .seconds(snapshot.isPlaying ? 1 : 2))
                }
                continuation.finish()
            }
            continuation.onTermination = { [weak self] _ in self?.stop() }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
        observers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        observers.removeAll()
    }
}

/// Serializes polling so a notification-triggered poll never overlaps a timed one.
actor Poller {
    private let sources: [PlayerSource]
    private var lastActive: PlayerKind?
    /// Last failure reported per player, so a persistent error is reported once, not every tick.
    private var reported: [PlayerKind: ScriptError] = [:]

    init(sources: [PlayerSource]) { self.sources = sources }

    /// Picks the snapshot to show: a playing player wins, then the last active one.
    func poll() async -> (PlaybackSnapshot, newProblems: [(PlayerKind, ScriptError)]) {
        var snapshots: [PlaybackSnapshot] = []
        var problems: [(PlayerKind, ScriptError)] = []

        for source in sources {
            guard let result = await source.snapshot() else { reported[source.kind] = nil; continue }
            switch result {
            case .success(let s):
                reported[source.kind] = nil
                if s.track != nil { snapshots.append(s) }
            case .failure(let error):
                if reported[source.kind] != error {
                    reported[source.kind] = error
                    problems.append((source.kind, error))
                }
            }
        }

        let playing = snapshots.filter(\.isPlaying)
        let chosen = playing.first(where: { $0.track?.player == lastActive })
            ?? playing.first
            ?? snapshots.first(where: { $0.track?.player == lastActive })
            ?? snapshots.first
            ?? .idle
        if let player = chosen.track?.player { lastActive = player }
        return (chosen, problems)
    }
}
