import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import LyraCore

private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []
    func add(_ u: URL) { lock.withLock { urls.append(u) } }
    var all: [URL] { lock.withLock { urls } }
}

private struct StubHTTP: HTTPClient {
    var recorder = Recorder()
    var handler: @Sendable (URL) -> (Int, Data)
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url!
        recorder.add(url)
        let (status, data) = handler(url)
        return (data, HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

private func pngData(_ color: (CGFloat, CGFloat, CGFloat) = (0.9, 0.2, 0.3)) -> Data {
    let ctx = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: color.0, green: color.1, blue: color.2, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
    let data = NSMutableData()
    let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
    return data as Data
}

private func json(_ items: [[String: String]]) -> Data {
    try! JSONSerialization.data(withJSONObject: ["resultCount": items.count, "results": items])
}

private let cover = "https://is1-ssl.mzstatic.com/image/thumb/Music/abc/100x100bb.jpg"

private func track(_ title: String = "My Song", artist: String = "The Band", album: String = "Great Album") -> Track {
    Track(title: title, artist: artist, album: album, duration: 200, player: .appleMusic, id: "1")
}

/// A server that knows one album and serves a PNG for any image URL.
private func albumServer(_ items: [[String: String]]) -> StubHTTP {
    StubHTTP { url in
        url.host == "itunes.apple.com" ? (200, json(items)) : (200, pngData())
    }
}

final class ITunesArtworkProviderTests: XCTestCase {
    func testFindsTheAlbumCoverAndRequestsTheLargerSize() async throws {
        let http = albumServer([["collectionName": "Great Album", "artistName": "The Band", "artworkUrl100": cover]])
        let image = await ITunesArtworkProvider(http: http).artwork(for: track())
        XCTAssertNotNil(image)

        let requests = http.recorder.all
        XCTAssertEqual(requests.count, 2, "one search, one image download")
        let search = try XCTUnwrap(URLComponents(url: requests[0], resolvingAgainstBaseURL: false))
        XCTAssertEqual(search.queryItems?.first { $0.name == "term" }?.value, "The Band Great Album")
        XCTAssertEqual(search.queryItems?.first { $0.name == "entity" }?.value, "album")
        XCTAssertTrue(requests[1].absoluteString.contains("600x600bb"), "asks for the 600 px version")
    }

    func testFallsBackToTheSongWhenTheAlbumHasNoMatch() async {
        let http = StubHTTP { url in
            guard url.host == "itunes.apple.com" else { return (200, pngData()) }
            let entity = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "entity" }?.value
            if entity == "album" { return (200, json([])) }
            return (200, json([["trackName": "My Song", "artistName": "The Band", "artworkUrl100": cover]]))
        }
        let image = await ITunesArtworkProvider(http: http).artwork(for: track())
        XCTAssertNotNil(image)
        XCTAssertEqual(http.recorder.all.count, 3, "album search, song search, download")
    }

    func testWrongAlbumOrArtistIsNeverUsed() async {
        let wrongAlbum = albumServer([["collectionName": "Totally Different", "artistName": "The Band", "artworkUrl100": cover]])
        let a = await ITunesArtworkProvider(http: wrongAlbum).artwork(for: track())
        XCTAssertNil(a, "a different album by the same artist must not be shown")

        let wrongArtist = albumServer([["collectionName": "Great Album", "artistName": "Someone Else", "artworkUrl100": cover]])
        let b = await ITunesArtworkProvider(http: wrongArtist).artwork(for: track())
        XCTAssertNil(b, "the same album name by another artist must not be shown")
    }

    func testPicksTheMatchingResultAmongSeveral() async {
        let http = albumServer([
            ["collectionName": "Other", "artistName": "The Band", "artworkUrl100": "https://is1-ssl.mzstatic.com/wrong/100x100bb.jpg"],
            ["collectionName": "Great Album (Deluxe Edition)", "artistName": "The Band", "artworkUrl100": cover],
        ])
        _ = await ITunesArtworkProvider(http: http).artwork(for: track())
        XCTAssertTrue(http.recorder.all.last?.absoluteString.contains("/Music/abc/") == true)
    }

    func testDisabledSwitchMakesNoRequests() async {
        let http = albumServer([["collectionName": "Great Album", "artistName": "The Band", "artworkUrl100": cover]])
        let flag = ArtworkLookupSwitch(isEnabled: false)
        let image = await ITunesArtworkProvider(http: http, isEnabled: { flag.isEnabled }).artwork(for: track())
        XCTAssertNil(image)
        XCTAssertTrue(http.recorder.all.isEmpty, "nothing is sent while the lookup is off")

        flag.isEnabled = true
        let again = await ITunesArtworkProvider(http: http, isEnabled: { flag.isEnabled }).artwork(for: track())
        XCTAssertNotNil(again, "turning it back on takes effect immediately")
    }

    func testMultipleArtistsSearchByTheFirstOne() async throws {
        let http = albumServer([])
        _ = await ITunesArtworkProvider(http: http).artwork(for: track(artist: "The Band, Guest Singer"))
        let term = URLComponents(url: try XCTUnwrap(http.recorder.all.first), resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "term" }?.value
        XCTAssertEqual(term, "The Band Great Album")
    }

    func testEditionNoiseInTheAlbumNameIsIgnored() async {
        let http = albumServer([["collectionName": "Great Album", "artistName": "The Band", "artworkUrl100": cover]])
        let image = await ITunesArtworkProvider(http: http).artwork(for: track(album: "Great Album (Deluxe Version)"))
        XCTAssertNotNil(image)
    }

    func testTrackWithNoAlbumUsesTheSongSearchOnly() async {
        let http = StubHTTP { url in
            url.host == "itunes.apple.com"
                ? (200, json([["trackName": "My Song", "artistName": "The Band", "artworkUrl100": cover]]))
                : (200, pngData())
        }
        let image = await ITunesArtworkProvider(http: http).artwork(for: track(album: ""))
        XCTAssertNotNil(image)
        let entities = http.recorder.all.compactMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "entity" }?.value }
        XCTAssertEqual(entities, ["song"])
    }

    func testSpecialCharactersAreEncodedInTheQuery() async throws {
        let http = albumServer([])
        _ = await ITunesArtworkProvider(http: http).artwork(for: track("Rock & Roll's Edge", artist: "The Band", album: "A&B: 100%"))
        let url = try XCTUnwrap(http.recorder.all.first)
        XCTAssertFalse(url.absoluteString.contains(" "), "spaces must be encoded")
        // If "&" or "%" were left raw, parsing the URL back would split or corrupt the value.
        let term = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "term" }?.value
        XCTAssertEqual(term, "The Band A&B: 100%", "the value round-trips intact")
    }

    func testFailuresGiveNilNotCrashes() async {
        for stub in [
            StubHTTP { _ in (500, Data()) },
            StubHTTP { _ in (200, Data("not json".utf8)) },
            StubHTTP { _ in (404, Data()) },
        ] {
            let image = await ITunesArtworkProvider(http: stub).artwork(for: track())
            XCTAssertNil(image)
        }
        // The search works but the image download fails or is garbage.
        let badImage = StubHTTP { url in
            url.host == "itunes.apple.com"
                ? (200, json([["collectionName": "Great Album", "artistName": "The Band", "artworkUrl100": cover]]))
                : (200, Data("not an image".utf8))
        }
        let result = await ITunesArtworkProvider(http: badImage).artwork(for: track())
        XCTAssertNil(result)
    }

    func testOnlyAppleImageHostsAreFollowed() async {
        let http = albumServer([["collectionName": "Great Album", "artistName": "The Band", "artworkUrl100": "https://evil.example.com/100x100bb.jpg"]])
        let image = await ITunesArtworkProvider(http: http).artwork(for: track())
        XCTAssertNil(image)
        XCTAssertTrue(http.recorder.all.allSatisfy { $0.host == "itunes.apple.com" }, "no request goes to the foreign host")
        XCTAssertNil(ITunesArtworkProvider.largerArtworkURL("http://is1-ssl.mzstatic.com/100x100bb.jpg"), "plain http is refused")
        XCTAssertNotNil(ITunesArtworkProvider.largerArtworkURL(cover))
    }

    func testNameMatching() {
        XCTAssertTrue(ITunesArtworkProvider.matches("Café #3", "cafe 3"))
        XCTAssertTrue(ITunesArtworkProvider.matches("Greatest Hits Vol. 2 (Remastered)", "Greatest Hits Vol. 2"))
        XCTAssertFalse(ITunesArtworkProvider.matches("Live", "Live at the Apollo Theater"), "a short name must not match a long one")
        XCTAssertFalse(ITunesArtworkProvider.matches("Abbey Road", "Let It Be"))
        XCTAssertFalse(ITunesArtworkProvider.matches(nil, "x"))
        XCTAssertFalse(ITunesArtworkProvider.matches("", ""))
    }
}

final class ChainedArtworkProviderTests: XCTestCase {
    private struct Fixed: ArtworkProvider {
        var image: CGImage?
        var onCall: @Sendable () -> Void = {}
        func artwork(for track: Track) async -> CGImage? { onCall(); return image }
    }

    private func image() -> CGImage { ArtworkDecoder.image(from: pngData())! }

    func testFirstNonNilWinsAndLaterProvidersAreSkipped() async {
        let secondCalls = Recorder()
        let chain = ChainedArtworkProvider([Fixed(image: nil), Fixed(image: image()), Fixed(image: image(), onCall: { secondCalls.add(URL(string: "x:")!) })])
        let result = await chain.artwork(for: track())
        XCTAssertNotNil(result)
        XCTAssertTrue(secondCalls.all.isEmpty, "the third provider is never asked")
    }

    func testAllEmptyGivesNilAndEmptyChainIsNil() async {
        let none = await ChainedArtworkProvider([Fixed(image: nil), Fixed(image: nil)]).artwork(for: track())
        XCTAssertNil(none)
        let empty = await ChainedArtworkProvider([]).artwork(for: track())
        XCTAssertNil(empty)
    }
}
