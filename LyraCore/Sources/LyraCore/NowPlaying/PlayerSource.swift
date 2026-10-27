import AppKit

/// One music app that can report what it is playing.
public protocol PlayerSource: Sendable {
    var kind: PlayerKind { get }
    var bundleID: String { get }
    /// Distributed notification the app posts when playback changes, if any.
    var changeNotification: String? { get }
    /// nil when the app isn't running or can't be read.
    func snapshot() async -> Result<PlaybackSnapshot, ScriptError>?
}

/// Reads a player through AppleScript. Subclass-free: the per-app differences are data.
public struct ScriptedPlayerSource: PlayerSource {
    public let kind: PlayerKind
    public let bundleID: String
    public let changeNotification: String?
    let script: String
    /// Divides the app's duration value to get seconds (Spotify reports ms, Music reports s).
    private let durationScale: Double
    private let runner = AppleScriptRunner()

    // ASCII 31 (unit separator) can't appear in track metadata, unlike "|" or ",".
    private static let sep = "\u{1F}"

    public static let spotify = ScriptedPlayerSource(
        kind: .spotify,
        bundleID: "com.spotify.client",
        changeNotification: "com.spotify.client.PlaybackStateChanged",
        durationScale: 1000,
        script: """
        tell application "Spotify"
            set stateText to (player state as string)
            if stateText is "stopped" then return stateText
            set t to current track
            set sep to (ASCII character 31)
            return stateText & sep & (name of t) & sep & (artist of t) & sep & (album of t) & sep & ((duration of t) as integer) & sep & ((player position * 1000) as integer) & sep & (id of t) & sep & ""
        end tell
        """)

    public static let appleMusic = ScriptedPlayerSource(
        kind: .appleMusic,
        bundleID: "com.apple.Music",
        changeNotification: "com.apple.Music.playerInfo",
        durationScale: 1000,
        script: """
        tell application "Music"
            set stateText to (player state as string)
            if stateText is "stopped" then return stateText
            set t to current track
            set sep to (ASCII character 31)
            return stateText & sep & (name of t) & sep & (artist of t) & sep & (album of t) & sep & ((duration of t * 1000) as integer) & sep & ((player position * 1000) as integer) & sep & ((database ID of t) as string) & sep & (genre of t)
        end tell
        """)

    init(kind: PlayerKind, bundleID: String, changeNotification: String?, durationScale: Double, script: String) {
        self.kind = kind
        self.bundleID = bundleID
        self.changeNotification = changeNotification
        self.durationScale = durationScale
        // Apple events wait two minutes by default; a busy player must not stall polling.
        self.script = "with timeout of 3 seconds\n\(script)\nend timeout"
    }

    public func snapshot() async -> Result<PlaybackSnapshot, ScriptError>? {
        // Never script an app that isn't running: that would launch it.
        // A live query: `NSWorkspace.runningApplications` is KVO-backed and can go
        // stale in a process that isn't spinning an AppKit run loop (the CLI).
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else {
            Debug.log("\(kind): not running")
            return nil
        }

        let started = Date()
        let result = await runner.run(script)
        let finished = Date()
        // The player answered somewhere in the middle of the call.
        let capturedAt = started.addingTimeInterval(finished.timeIntervalSince(started) / 2)

        switch result {
        case .failure(let e):
            Debug.log("\(kind): script failed \(e)")
            return .failure(e)
        case .success(let out):
            Debug.log(String(format: "%@ (%.2fs): %@", "\(kind)", finished.timeIntervalSince(started), out.replacingOccurrences(of: Self.sep, with: " | ")))
            return .success(Self.parse(out, kind: kind, capturedAt: capturedAt, durationScale: durationScale))
        }
    }

    static func parse(_ output: String, kind: PlayerKind, capturedAt: Date, durationScale: Double = 1000) -> PlaybackSnapshot {
        let parts = output.components(separatedBy: sep)
        guard parts.count >= 7 else { return PlaybackSnapshot(track: nil, position: 0, isPlaying: false, capturedAt: capturedAt) }
        let track = Track(
            title: parts[1], artist: parts[2], album: parts[3],
            duration: (Double(parts[4]) ?? 0) / durationScale,
            player: kind, genre: parts.count > 7 ? parts[7] : "", id: parts[6])
        return PlaybackSnapshot(
            track: track,
            position: (Double(parts[5]) ?? 0) / 1000,
            isPlaying: parts[0] == "playing",
            capturedAt: capturedAt)
    }
}
