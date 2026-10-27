import Foundation
import CoreGraphics

/// A thread-safe on/off flag the settings can flip while lookups are running on other threads.
public final class ArtworkLookupSwitch: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Bool

    public init(isEnabled: Bool = true) { value = isEnabled }

    public var isEnabled: Bool {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}

/// Tries each provider in order and returns the first image found.
public struct ChainedArtworkProvider: ArtworkProvider {
    private let providers: [ArtworkProvider]

    public init(_ providers: [ArtworkProvider]) { self.providers = providers }

    public func artwork(for track: Track) async -> CGImage? {
        for provider in providers {
            if let image = await provider.artwork(for: track) { return image }
        }
        return nil
    }
}

/// Cover art from Apple's public iTunes Search API, for tracks the player can't give art for
/// (streamed Apple Music tracks report none through scripting).
///
/// This sends the artist and album (or title) to itunes.apple.com, so it can be switched off.
/// A result is only used when its album or title really matches: showing no cover is better
/// than showing the wrong one, and wrong art would also give wrong colors.
public struct ITunesArtworkProvider: ArtworkProvider {
    private let http: HTTPClient
    private let baseURL: URL
    private let isEnabled: @Sendable () -> Bool
    /// Cover images are a few hundred KB; refuse anything absurd.
    private let maxImageBytes = 8_000_000

    public init(http: HTTPClient = URLSessionHTTPClient(),
                baseURL: URL = URL(string: "https://itunes.apple.com")!,
                isEnabled: @escaping @Sendable () -> Bool = { true }) {
        self.http = http
        self.baseURL = baseURL
        self.isEnabled = isEnabled
    }

    struct Response: Decodable {
        struct Item: Decodable {
            var collectionName: String?
            var artistName: String?
            var trackName: String?
            var artworkUrl100: String?
        }
        var results: [Item]
    }

    public func artwork(for track: Track) async -> CGImage? {
        guard isEnabled() else { return nil }
        let artist = TrackQuery.primaryArtist(track.artist)
        let title = TrackQuery.cleanTitle(track.title)
        let album = TrackQuery.cleanTitle(track.album)
        guard !artist.isEmpty else { return nil }

        // The album is the better key: one cover for every track on it. Fall back to the song.
        if !album.isEmpty,
           let url = await bestArtworkURL(term: "\(artist) \(album)", entity: "album", artist: artist) { item in
               Self.matches(item.collectionName, album)
           },
           let image = await download(url) { return image }

        if !title.isEmpty,
           let url = await bestArtworkURL(term: "\(artist) \(title)", entity: "song", artist: artist) { item in
               Self.matches(item.trackName, title)
           },
           let image = await download(url) { return image }
        return nil
    }

    // MARK: - Search

    private func bestArtworkURL(term: String, entity: String, artist: String,
                                nameMatches: (Response.Item) -> Bool) async -> URL? {
        var components = URLComponents(url: baseURL.appendingPathComponent("search"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: entity),
            URLQueryItem(name: "limit", value: "8"),
        ]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        guard let (data, response) = try? await http.data(for: request), response.statusCode == 200,
              let decoded = try? JSONDecoder().decode(Response.self, from: data) else { return nil }

        let wantedArtist = Self.normalize(artist)
        let match = decoded.results.first { item in
            guard nameMatches(item), let itemArtist = item.artistName, item.artworkUrl100 != nil else { return false }
            let a = Self.normalize(itemArtist)
            return !wantedArtist.isEmpty && (a.contains(wantedArtist) || wantedArtist.contains(a))
        }
        guard let small = match?.artworkUrl100 else { return nil }
        return Self.largerArtworkURL(small)
    }

    // MARK: - Download

    private func download(_ url: URL) async -> CGImage? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        guard let (data, response) = try? await http.data(for: request), response.statusCode == 200,
              data.count <= maxImageBytes else { return nil }
        return ArtworkDecoder.image(from: data)
    }

    // MARK: - Matching helpers

    /// Lowercase letters and digits only, with accents folded: "Café #3" and "cafe 3" compare equal.
    static func normalize(_ s: String) -> String {
        String(s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    /// True when the result's name is the wanted name (ignoring punctuation and case). Containment
    /// is allowed in one direction only for longer names, so "Greatest Hits Vol. 2" still matches
    /// "Greatest Hits Vol. 2 (Remastered)" without "Live" matching every album that contains it.
    static func matches(_ candidate: String?, _ wanted: String) -> Bool {
        guard let candidate else { return false }
        let c = normalize(candidate), w = normalize(wanted)
        guard !c.isEmpty, !w.isEmpty else { return false }
        if c == w { return true }
        return w.count >= 6 && (c.hasPrefix(w) || w.hasPrefix(c) && c.count >= 6)
    }

    /// The API returns a 100 px thumbnail URL; the same path serves bigger sizes. Only Apple's
    /// image host is accepted, so a hostile or broken response can't point the app elsewhere.
    static func largerArtworkURL(_ small: String) -> URL? {
        let big = small.replacingOccurrences(of: "100x100bb", with: "600x600bb")
        guard let url = URL(string: big), url.scheme == "https",
              let host = url.host, host == "mzstatic.com" || host.hasSuffix(".mzstatic.com") else { return nil }
        return url
    }
}
