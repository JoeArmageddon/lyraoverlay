import Foundation
import CryptoKit

public struct TrackQuery: Hashable, Sendable {
    public var title: String
    public var artist: String
    public var album: String
    public var duration: TimeInterval

    public init(title: String, artist: String, album: String = "", duration: TimeInterval = 0) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
    }

    public init(track: Track) {
        self.init(title: track.title, artist: track.artist, album: track.album, duration: track.duration)
    }

    /// Strips edition noise and secondary artists, which commonly break exact lookups.
    public var normalized: TrackQuery {
        TrackQuery(title: Self.cleanTitle(title), artist: Self.primaryArtist(artist), album: "", duration: duration)
    }

    /// Stable cache key. Ignores album and duration, which vary between releases.
    public var cacheKey: String {
        let n = normalized
        let raw = "\(n.artist.lowercased())|\(n.title.lowercased())"
        return SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Normalizing

    private static let bracketNoise = try! NSRegularExpression(
        pattern: #"\s*[\(\[][^\)\]]*(remaster|live|version|edit|mono|stereo|feat\.?|ft\.?|with|deluxe|bonus)[^\)\]]*[\)\]]"#,
        options: [.caseInsensitive])
    private static let dashNoise = try! NSRegularExpression(
        pattern: #"\s+-\s+.*(remaster|version|edit|mono|stereo|single|live).*$"#,
        options: [.caseInsensitive])

    static func cleanTitle(_ title: String) -> String {
        var s = title
        for re in [bracketNoise, dashNoise] {
            s = re.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: "")
        }
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? title : trimmed
    }

    static func primaryArtist(_ artist: String) -> String {
        for sep in [", ", " & ", "; ", " feat. ", " ft. ", " x "] {
            if let r = artist.range(of: sep) { return String(artist[..<r.lowerBound]) }
        }
        return artist
    }
}
