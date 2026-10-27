import Foundation

public enum CacheLookup: Equatable, Sendable {
    case hit(LyricsDocument)
    /// A recent lookup found nothing; don't hit the network again yet.
    case knownMiss
    case none
}

/// On-disk lyrics cache, one JSON file per track.
public actor LyricsCache {
    private struct Entry: Codable {
        var document: LyricsDocument?
        var fetchedAt: Date
    }

    private let directory: URL
    private let missTTL: TimeInterval
    private let now: @Sendable () -> Date

    public init(directory: URL? = nil, missTTL: TimeInterval = 24 * 3600, now: @escaping @Sendable () -> Date = { Date() }) {
        self.directory = directory ?? Self.defaultDirectory
        self.missTTL = missTTL
        self.now = now
    }

    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lyra/LyricsCache", isDirectory: true)
    }

    public func lookup(_ key: String) -> CacheLookup {
        guard let data = try? Data(contentsOf: url(for: key)),
              let entry = try? JSONDecoder().decode(Entry.self, from: data) else { return .none }
        if let doc = entry.document { return .hit(doc) }
        return now().timeIntervalSince(entry.fetchedAt) < missTTL ? .knownMiss : .none
    }

    public func store(_ document: LyricsDocument?, for key: String) {
        let entry = Entry(document: document, fetchedAt: now())
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(entry).write(to: url(for: key), options: .atomic)
        } catch {
            // Caching is best-effort; a failed write only costs a refetch.
        }
    }

    public func remove(_ key: String) {
        try? FileManager.default.removeItem(at: url(for: key))
    }

    private func url(for key: String) -> URL {
        directory.appendingPathComponent("\(key).json")
    }
}
