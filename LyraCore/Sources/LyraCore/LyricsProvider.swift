import Foundation

public protocol LyricsProvider: Sendable {
    var name: String { get }
    /// Returns nil when the provider has no lyrics for the track. Throws on
    /// transient failures (network, server errors) so callers don't cache a miss.
    func fetch(for query: TrackQuery) async throws -> LyricsDocument?
}

public protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}
