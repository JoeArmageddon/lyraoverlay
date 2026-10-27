import Foundation

/// Lyrics from https://lrclib.net, a free community database of synced (LRC) lyrics.
public struct LRCLIBProvider: LyricsProvider {
    public let name = "lrclib"
    private let http: HTTPClient
    private let baseURL: URL
    /// Matches within this many seconds count as the same recording.
    private let durationTolerance: TimeInterval = 4

    public init(http: HTTPClient = URLSessionHTTPClient(), baseURL: URL = URL(string: "https://lrclib.net/api")!) {
        self.http = http
        self.baseURL = baseURL
    }

    struct Entry: Decodable {
        var trackName: String?
        var artistName: String?
        var duration: Double?
        var instrumental: Bool?
        var plainLyrics: String?
        var syncedLyrics: String?
    }

    public func fetch(for query: TrackQuery) async throws -> LyricsDocument? {
        // Exact lookup first: it needs album and duration, and is the most precise.
        // A failing exact lookup (503s are common) must not hide what search can find.
        if !query.album.isEmpty, query.duration > 0,
           let entry = try? await get(query) {
            return document(from: entry, trackDuration: query.duration)
        }
        let results = try await search(query)
        guard let best = pickBest(results, for: query) else { return nil }
        return document(from: best, trackDuration: query.duration > 0 ? query.duration : best.duration)
    }

    // MARK: - Requests

    private func get(_ q: TrackQuery) async throws -> Entry? {
        let items = [
            URLQueryItem(name: "track_name", value: q.title),
            URLQueryItem(name: "artist_name", value: q.artist),
            URLQueryItem(name: "album_name", value: q.album),
            URLQueryItem(name: "duration", value: String(Int(q.duration.rounded()))),
        ]
        guard let (data, status) = try await request("get", items) else { return nil }
        guard status == 200 else { return nil }
        return try JSONDecoder().decode(Entry.self, from: data)
    }

    private func search(_ q: TrackQuery) async throws -> [Entry] {
        let items = [
            URLQueryItem(name: "track_name", value: q.title),
            URLQueryItem(name: "artist_name", value: q.artist),
        ]
        guard let (data, status) = try await request("search", items), status == 200 else { return [] }
        return try JSONDecoder().decode([Entry].self, from: data)
    }

    /// Returns nil for 404 (a definite "no"), throws for other failures.
    private func request(_ path: String, _ items: [URLQueryItem]) async throws -> (Data, Int)? {
        var comps = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        comps.queryItems = items
        var req = URLRequest(url: comps.url!)
        req.timeoutInterval = 10
        req.setValue("Lyra/0.1 (open-source lyrics overlay)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await http.data(for: req)
        switch response.statusCode {
        case 200: return (data, 200)
        case 404: return nil
        default: throw URLError(.badServerResponse)
        }
    }

    // MARK: - Mapping

    /// Prefers synced lyrics, then the closest duration within tolerance.
    func pickBest(_ entries: [Entry], for q: TrackQuery) -> Entry? {
        let usable = entries.filter { $0.syncedLyrics?.isEmpty == false || $0.plainLyrics?.isEmpty == false || $0.instrumental == true }
        let inTolerance = usable.filter { e in
            guard q.duration > 0, let d = e.duration else { return true }
            return abs(d - q.duration) <= durationTolerance
        }
        return inTolerance.sorted { a, b in
            let aSynced = a.syncedLyrics?.isEmpty == false, bSynced = b.syncedLyrics?.isEmpty == false
            if aSynced != bSynced { return aSynced }
            return abs((a.duration ?? 0) - q.duration) < abs((b.duration ?? 0) - q.duration)
        }.first
    }

    func document(from e: Entry, trackDuration: TimeInterval?) -> LyricsDocument? {
        if e.instrumental == true {
            return LyricsDocument(lines: [], isSynced: false, hasWordTiming: false, source: name, instrumental: true)
        }
        if let synced = e.syncedLyrics, !synced.isEmpty,
           var doc = LRCParser.parse(synced, trackDuration: trackDuration, source: name) {
            doc.plainText = e.plainLyrics
            return doc
        }
        if let plain = e.plainLyrics, !plain.isEmpty {
            return LyricsDocument(lines: [], isSynced: false, hasWordTiming: false, source: name, plainText: plain)
        }
        return nil
    }
}
