import Foundation

/// Looks lyrics up through the cache, then each provider in order.
public actor LyricsService {
    private let providers: [LyricsProvider]
    private let cache: LyricsCache

    public init(providers: [LyricsProvider] = [LRCLIBProvider()], cache: LyricsCache = LyricsCache()) {
        self.providers = providers
        self.cache = cache
    }

    /// Returns nil when no provider has lyrics. A miss is cached only if every
    /// provider answered cleanly, so a network blip never hides lyrics for a day.
    public func lyrics(for query: TrackQuery) async -> LyricsDocument? {
        let key = query.cacheKey
        switch await cache.lookup(key) {
        case .hit(let doc): return doc
        case .knownMiss: return nil
        case .none: break
        }

        var attempts = [query]
        if query.normalized != query { attempts.append(query.normalized) }

        var hadError = false
        for attempt in attempts {
            for provider in providers {
                do {
                    if let doc = try await provider.fetch(for: attempt) {
                        await cache.store(doc, for: key)
                        return doc
                    }
                } catch {
                    hadError = true
                }
            }
        }
        if !hadError { await cache.store(nil, for: key) }
        return nil
    }
}
