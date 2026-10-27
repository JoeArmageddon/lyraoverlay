import Foundation
import CoreGraphics
import ImageIO

public protocol ArtworkProvider: Sendable {
    /// The artwork of `track`, or nil when there is none or it can't be read.
    func artwork(for track: Track) async -> CGImage?
}

/// Runs a script and returns its output. A seam so artwork lookup is testable without the apps.
protocol ScriptRunning: Sendable {
    func run(_ source: String) async -> Result<String, ScriptError>
}

extension AppleScriptRunner: ScriptRunning {}

enum ArtworkDecoder {
    static func image(from data: Data) -> CGImage? {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

/// Reads artwork from whichever player is playing the track.
///
/// - Spotify exposes an artwork URL, which is downloaded.
/// - Apple Music exposes the raw image bytes, which a script writes to a temp file
///   (osascript output is text, so bytes can't come back directly).
/// Either way the script also returns the track id, and a mismatch means the track
/// changed mid-lookup, so the result is discarded rather than showing the wrong colors.
public struct PlayerArtworkProvider: ArtworkProvider {
    private static let sep = "\u{1F}"

    private let http: HTTPClient
    private let runner: ScriptRunning
    private let tempDirectory: URL

    public init(http: HTTPClient = URLSessionHTTPClient()) {
        self.init(http: http, runner: AppleScriptRunner(), tempDirectory: FileManager.default.temporaryDirectory)
    }

    init(http: HTTPClient, runner: ScriptRunning, tempDirectory: URL) {
        self.http = http
        self.runner = runner
        self.tempDirectory = tempDirectory
    }

    public func artwork(for track: Track) async -> CGImage? {
        switch track.player {
        case .spotify: return await spotifyArtwork(for: track)
        case .appleMusic: return await musicArtwork(for: track)
        }
    }

    // MARK: - Spotify

    static let spotifyScript = """
    with timeout of 3 seconds
        tell application "Spotify"
            set theTrack to current track
            set sep to (ASCII character 31)
            return (id of theTrack) & sep & (artwork url of theTrack)
        end tell
    end timeout
    """

    private func spotifyArtwork(for track: Track) async -> CGImage? {
        guard case .success(let out) = await runner.run(Self.spotifyScript) else { return nil }
        let parts = out.components(separatedBy: Self.sep)
        guard parts.count >= 2, parts[0] == track.id, let url = URL(string: parts[1]) else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        guard let (data, response) = try? await http.data(for: request), response.statusCode == 200 else { return nil }
        return ArtworkDecoder.image(from: data)
    }

    // MARK: - Apple Music

    /// `path` is where the script writes the image bytes.
    static func musicScript(writingTo path: String) -> String {
        let escaped = path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return """
        with timeout of 3 seconds
            tell application "Music"
                set theTrack to current track
                set trackID to ((database ID of theTrack) as string)
                set sep to (ASCII character 31)
                if (count of artworks of theTrack) is 0 then return trackID & sep & "none"
                set artData to (raw data of artwork 1 of theTrack)
            end tell
            set fileRef to open for access (POSIX file "\(escaped)") with write permission
            try
                set eof of fileRef to 0
                write artData to fileRef
                close access fileRef
            on error
                try
                    close access fileRef
                end try
                return trackID & sep & "error"
            end try
            return trackID & sep & "ok"
        end timeout
        """
    }

    private func musicArtwork(for track: Track) async -> CGImage? {
        let file = tempDirectory.appendingPathComponent("lyra-artwork-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: file) }

        guard case .success(let out) = await runner.run(Self.musicScript(writingTo: file.path)) else { return nil }
        let parts = out.components(separatedBy: Self.sep)
        guard parts.count >= 2, parts[0] == track.id, parts[1] == "ok",
              let data = try? Data(contentsOf: file) else { return nil }
        return ArtworkDecoder.image(from: data)
    }
}
