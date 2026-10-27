import Foundation
import AppKit

public enum PlayerCommand: Sendable {
    case playPause
    case next
    case previous
}

/// Transport controls for Spotify and Apple Music.
public enum PlayerControl {
    private static let bundleIDs: [PlayerKind: String] = [.spotify: "com.spotify.client", .appleMusic: "com.apple.Music"]

    /// Sends the command. Returns false when the app isn't running (it is never launched just to
    /// receive a command) or the script failed.
    public static func send(_ command: PlayerCommand, to player: PlayerKind) async -> Bool {
        guard let bundleID = bundleIDs[player],
              !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else { return false }
        if case .success = await AppleScriptRunner().run(script(for: command, player: player)) { return true }
        return false
    }

    /// Jumps the current track to `seconds`. Returns false when the app isn't running or the script
    /// failed. Never launches the app.
    public static func seek(to seconds: TimeInterval, player: PlayerKind) async -> Bool {
        guard seconds.isFinite, let bundleID = bundleIDs[player],
              !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else { return false }
        if case .success = await AppleScriptRunner().run(seekScript(seconds: seconds, player: player)) { return true }
        return false
    }

    /// Both players take `player position` in seconds. The position goes in as whole milliseconds
    /// divided by 1000 inside the script: a decimal literal like "12.5" would break in a locale
    /// that writes a comma.
    static func seekScript(seconds: TimeInterval, player: PlayerKind) -> String {
        let app = player == .spotify ? "Spotify" : "Music"
        let milliseconds = Int((max(0, seconds) * 1000).rounded())
        return "with timeout of 3 seconds\ntell application \"\(app)\" to set player position to (\(milliseconds) / 1000)\nend timeout"
    }

    /// The AppleScript for a command. No variables, so nothing can clash with an app's own terms.
    static func script(for command: PlayerCommand, player: PlayerKind) -> String {
        let app = player == .spotify ? "Spotify" : "Music"
        let verb: String
        switch command {
        case .playPause: verb = "playpause"
        case .next: verb = "next track"
        case .previous: verb = "previous track"
        }
        // Apple events wait two minutes by default; a busy player must not stall the UI.
        return "with timeout of 3 seconds\ntell application \"\(app)\" to \(verb)\nend timeout"
    }
}
