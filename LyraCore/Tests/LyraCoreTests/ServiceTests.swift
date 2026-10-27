import AppKit
import XCTest
@testable import LyraCore

private struct MockHTTP: HTTPClient {
    var handler: @Sendable (URLRequest) throws -> (Int, String)
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (status, body) = try handler(request)
        let resp = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), resp)
    }
}

private final class CountingProvider: LyricsProvider, @unchecked Sendable {
    let name = "counting"
    private let lock = NSLock()
    private var _calls = 0
    var calls: Int { lock.withLock { _calls } }
    let result: Result<LyricsDocument?, Error>
    init(_ result: Result<LyricsDocument?, Error>) { self.result = result }
    func fetch(for query: TrackQuery) async throws -> LyricsDocument? {
        lock.withLock { _calls += 1 }
        return try result.get()
    }
}

private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var t = Date(timeIntervalSince1970: 1_000_000)
    var now: Date { lock.withLock { t } }
    func advance(_ s: TimeInterval) { lock.withLock { t = t.addingTimeInterval(s) } }
}

private func tempDir() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("lyra-tests-\(UUID().uuidString)")
}

private let sampleDoc = LRCParser.parse("[00:01.00]Hello world", source: "test")!

final class TrackQueryTests: XCTestCase {
    func testCleanTitle() {
        XCTAssertEqual(TrackQuery.cleanTitle("Song (Remastered 2011)"), "Song")
        XCTAssertEqual(TrackQuery.cleanTitle("Song - 2011 Remaster"), "Song")
        XCTAssertEqual(TrackQuery.cleanTitle("Song (feat. Someone)"), "Song")
        XCTAssertEqual(TrackQuery.cleanTitle("Song [Live]"), "Song")
        XCTAssertEqual(TrackQuery.cleanTitle("Plain Title"), "Plain Title")
        XCTAssertEqual(TrackQuery.cleanTitle("(Remastered)"), "(Remastered)", "never reduce a title to nothing")
    }

    func testPrimaryArtist() {
        XCTAssertEqual(TrackQuery.primaryArtist("A, B"), "A")
        XCTAssertEqual(TrackQuery.primaryArtist("A & B"), "A")
        XCTAssertEqual(TrackQuery.primaryArtist("Solo"), "Solo")
    }

    func testCacheKeyIgnoresEditionAlbumAndCase() {
        let a = TrackQuery(title: "Song (Live)", artist: "Band", album: "X", duration: 200)
        let b = TrackQuery(title: "song", artist: "BAND, Guest", album: "Y", duration: 201)
        XCTAssertEqual(a.cacheKey, b.cacheKey)
        XCTAssertNotEqual(a.cacheKey, TrackQuery(title: "Other", artist: "Band").cacheKey)
    }
}

final class PlayerParsingTests: XCTestCase {
    func testParsesFullOutput() {
        let out = ["playing", "Song", "Artist", "Album", "200000", "12500", "id1", "Rock"].joined(separator: "\u{1F}")
        let snap = ScriptedPlayerSource.parse(out, kind: .appleMusic, capturedAt: Date())
        XCTAssertEqual(snap.track?.title, "Song")
        XCTAssertEqual(snap.track?.duration, 200)
        XCTAssertEqual(snap.position, 12.5)
        XCTAssertEqual(snap.track?.genre, "Rock")
        XCTAssertTrue(snap.isPlaying)
    }

    func testPausedAndMissingGenre() {
        let out = ["paused", "S", "A", "B", "1000", "0", "x", ""].joined(separator: "\u{1F}")
        let snap = ScriptedPlayerSource.parse(out, kind: .spotify, capturedAt: Date())
        XCTAssertFalse(snap.isPlaying)
        XCTAssertEqual(snap.track?.genre, "")
    }

    /// Regression: an AppleScript syntax error (a variable named `st` clashed with
    /// the Music dictionary) made the monitor silently report "nothing playing".
    func testPlayerScriptsCompile() throws {
        for source in [ScriptedPlayerSource.spotify, ScriptedPlayerSource.appleMusic] {
            guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleID) != nil else { continue }
            var error: NSDictionary?
            let script = try XCTUnwrap(NSAppleScript(source: source.script))
            XCTAssertTrue(script.compileAndReturnError(&error), "\(source.kind) script failed to compile: \(String(describing: error))")
        }
    }

    func testOsascriptErrorMapping() {
        XCTAssertEqual(AppleScriptRunner.error(fromStderr: "execution error: Not authorized to send Apple events to Music. (-1743)\n"), .notAuthorized)
        XCTAssertEqual(AppleScriptRunner.error(fromStderr: "execution error: Can't get track. (-1728)"), .failed(code: -1728, message: "execution error: Can't get track. (-1728)"))
        XCTAssertEqual(AppleScriptRunner.error(fromStderr: "garbage"), .failed(code: -1, message: "garbage"))
    }

    func testRunnerReturnsScriptOutputAndTimesOut() async {
        let ok = await AppleScriptRunner().run(#"return "hi" & (ASCII character 31) & "there""#)
        XCTAssertEqual(ok, .success("hi\u{1F}there"))

        let slow = await AppleScriptRunner(timeout: 0.5).run("delay 5\nreturn \"late\"")
        guard case .failure(.failed(let code, _)) = slow else { return XCTFail("expected timeout, got \(slow)") }
        XCTAssertEqual(code, -2)
    }

    func testStoppedOutputHasNoTrack() {
        XCTAssertNil(ScriptedPlayerSource.parse("stopped", kind: .spotify, capturedAt: Date()).track)
    }

    func testPositionExtrapolatesOnlyWhilePlaying() {
        let t0 = Date()
        let playing = PlaybackSnapshot(track: nil, position: 10, isPlaying: true, capturedAt: t0)
        XCTAssertEqual(playing.position(at: t0.addingTimeInterval(2)), 12, accuracy: 0.001)
        let paused = PlaybackSnapshot(track: nil, position: 10, isPlaying: false, capturedAt: t0)
        XCTAssertEqual(paused.position(at: t0.addingTimeInterval(2)), 10)
    }
}

final class LRCLIBProviderTests: XCTestCase {
    private let synced = #"{"trackName":"Song","artistName":"Band","duration":200,"instrumental":false,"plainLyrics":"Hello","syncedLyrics":"[00:01.00]Hello world"}"#

    func testExactLookupReturnsSyncedDocument() async throws {
        let http = MockHTTP { req in
            XCTAssertTrue(req.url!.path.hasSuffix("/get"))
            XCTAssertNotNil(req.value(forHTTPHeaderField: "User-Agent"))
            return (200, self.synced)
        }
        let doc = try await LRCLIBProvider(http: http).fetch(for: TrackQuery(title: "Song", artist: "Band", album: "Alb", duration: 200))
        XCTAssertEqual(doc?.lines.count, 1)
        XCTAssertEqual(doc?.source, "lrclib")
        XCTAssertEqual(doc?.plainText, "Hello")
    }

    func testFallsBackToSearchAndPicksSyncedWithinTolerance() async throws {
        let results = """
        [{"trackName":"Song","artistName":"Band","duration":260,"plainLyrics":"x","syncedLyrics":"[00:01.00]wrong length"},
         {"trackName":"Song","artistName":"Band","duration":201,"plainLyrics":"x","syncedLyrics":null},
         {"trackName":"Song","artistName":"Band","duration":199,"plainLyrics":"x","syncedLyrics":"[00:02.00]right one"}]
        """
        let http = MockHTTP { req in
            req.url!.path.hasSuffix("/get") ? (404, "{}") : (200, results)
        }
        let doc = try await LRCLIBProvider(http: http).fetch(for: TrackQuery(title: "Song", artist: "Band", album: "Alb", duration: 200))
        XCTAssertEqual(doc?.lines.first?.text, "right one")
    }

    func testExactLookupServerErrorFallsBackToSearch() async throws {
        let http = MockHTTP { req in
            req.url!.path.hasSuffix("/get") ? (503, "unavailable") : (200, "[\(self.synced)]")
        }
        let doc = try await LRCLIBProvider(http: http).fetch(for: TrackQuery(title: "Song", artist: "Band", album: "Alb", duration: 200))
        XCTAssertEqual(doc?.lines.count, 1)
    }

    func testPlainOnlyIsUnsynced() async throws {
        let http = MockHTTP { _ in (200, #"[{"duration":200,"plainLyrics":"la la","syncedLyrics":null}]"#) }
        let doc = try await LRCLIBProvider(http: http).fetch(for: TrackQuery(title: "S", artist: "A", duration: 200))
        XCTAssertEqual(doc?.isSynced, false)
        XCTAssertEqual(doc?.plainText, "la la")
    }

    func testInstrumentalFlag() async throws {
        let http = MockHTTP { _ in (200, #"[{"duration":200,"instrumental":true}]"#) }
        let doc = try await LRCLIBProvider(http: http).fetch(for: TrackQuery(title: "S", artist: "A", duration: 200))
        XCTAssertEqual(doc?.instrumental, true)
    }

    func testNotFoundIsNilAndServerErrorThrows() async throws {
        let none = MockHTTP { _ in (404, "{}") }
        let missing = try await LRCLIBProvider(http: none).fetch(for: TrackQuery(title: "S", artist: "A", album: "B", duration: 100))
        XCTAssertNil(missing)

        let broken = MockHTTP { _ in (500, "oops") }
        do {
            _ = try await LRCLIBProvider(http: broken).fetch(for: TrackQuery(title: "S", artist: "A"))
            XCTFail("expected a throw on HTTP 500")
        } catch {}
    }
}

final class CacheAndServiceTests: XCTestCase {
    func testCacheRoundTripAndMissExpiry() async {
        let clock = Clock()
        let cache = LyricsCache(directory: tempDir(), missTTL: 100, now: { clock.now })

        let none = await cache.lookup("k")
        XCTAssertEqual(none, .none)

        await cache.store(sampleDoc, for: "k")
        let hit = await cache.lookup("k")
        XCTAssertEqual(hit, .hit(sampleDoc))

        await cache.store(nil, for: "m")
        let fresh = await cache.lookup("m")
        XCTAssertEqual(fresh, .knownMiss)
        clock.advance(101)
        let expired = await cache.lookup("m")
        XCTAssertEqual(expired, .none)
    }

    func testServiceServesSecondLookupFromCache() async {
        let provider = CountingProvider(.success(sampleDoc))
        let service = LyricsService(providers: [provider], cache: LyricsCache(directory: tempDir()))
        let q = TrackQuery(title: "Song", artist: "Band")
        let first = await service.lyrics(for: q)
        let second = await service.lyrics(for: q)
        XCTAssertEqual(first, sampleDoc)
        XCTAssertEqual(second, sampleDoc)
        XCTAssertEqual(provider.calls, 1)
    }

    func testCleanMissIsCached() async {
        let provider = CountingProvider(.success(nil))
        let service = LyricsService(providers: [provider], cache: LyricsCache(directory: tempDir()))
        let q = TrackQuery(title: "Song", artist: "Band")
        _ = await service.lyrics(for: q)
        let callsAfterFirst = provider.calls
        _ = await service.lyrics(for: q)
        XCTAssertEqual(provider.calls, callsAfterFirst, "a cached miss must not hit the provider again")
    }

    func testErrorIsNotCachedAsMiss() async {
        let provider = CountingProvider(.failure(URLError(.notConnectedToInternet)))
        let service = LyricsService(providers: [provider], cache: LyricsCache(directory: tempDir()))
        let q = TrackQuery(title: "Song", artist: "Band")
        let first = await service.lyrics(for: q)
        XCTAssertNil(first)
        let callsAfterFirst = provider.calls
        _ = await service.lyrics(for: q)
        XCTAssertGreaterThan(provider.calls, callsAfterFirst, "after a network error the next lookup must retry")
    }

    func testServiceRetriesWithNormalizedQuery() async {
        final class Picky: LyricsProvider, @unchecked Sendable {
            let name = "picky"
            func fetch(for query: TrackQuery) async throws -> LyricsDocument? {
                query.title == "Song" ? sampleDoc : nil
            }
        }
        let service = LyricsService(providers: [Picky()], cache: LyricsCache(directory: tempDir()))
        let doc = await service.lyrics(for: TrackQuery(title: "Song (Remastered 2011)", artist: "Band"))
        XCTAssertNotNil(doc)
    }
}
