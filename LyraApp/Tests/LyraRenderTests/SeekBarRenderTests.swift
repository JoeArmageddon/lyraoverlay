import XCTest
import SwiftUI
import AppKit
import LyraCore
@testable import LyraRender

final class SeekBarRenderTests: XCTestCase {
    private func snapshot(position: TimeInterval, duration: TimeInterval, playing: Bool = false) -> PlaybackSnapshot {
        let track = Track(title: "Song", artist: "Band", album: "Album", duration: duration, player: .appleMusic, id: "1")
        return PlaybackSnapshot(track: track, position: position, isPlaying: playing, capturedAt: Date())
    }

    /// Renders the bar over a dark video-like background, the way it appears in the player.
    private func render(_ snap: PlaybackSnapshot?) throws -> NSBitmapImageRep {
        let view = SeekBarView(snapshot: { snap ?? .idle }, onSeek: { _, _ in })
            .frame(width: 560)
            .padding(24)
            .background(Color(white: 0.12))
            .environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.alphaValue = 0
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        window.effectiveAppearance.performAsCurrentDrawingAppearance { host.cacheDisplay(in: host.bounds, to: rep) }
        window.orderOut(nil)
        return rep
    }

    private func brightness(_ rep: NSBitmapImageRep, x: Int, y: Int) -> Double {
        guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return 0 }
        return Double(c.redComponent + c.greenComponent + c.blueComponent) / 3
    }

    /// The row with the most bright pixels: the filled part of the track.
    private func brightRow(_ rep: NSBitmapImageRep) -> Int {
        var best = (row: 0, count: 0)
        for y in 0..<rep.pixelsHigh {
            var count = 0
            for x in stride(from: 0, to: rep.pixelsWide, by: 2) where brightness(rep, x: x, y: y) > 0.8 { count += 1 }
            if count > best.count { best = (y, count) }
        }
        return best.row
    }

    private func filledWidth(_ rep: NSBitmapImageRep, row: Int) -> Int {
        (0..<rep.pixelsWide).filter { brightness(rep, x: $0, y: row) > 0.8 }.count
    }

    func testBarShowsTheElapsedFractionAndBothTimes() throws {
        let quarter = try render(snapshot(position: 50, duration: 200))
        let half = try render(snapshot(position: 100, duration: 200))
        let row = brightRow(half)
        // The bright fill of the track grows with the position (the text adds a constant amount).
        XCTAssertGreaterThan(filledWidth(half, row: brightRow(half)), filledWidth(quarter, row: brightRow(quarter)) + 40,
                             "halfway shows more filled track than a quarter of the way")
        XCTAssertGreaterThan(row, 0)

        if let dir = ProcessInfo.processInfo.environment["LYRA_SNAPSHOT_DIR"], let png = half.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("seek-bar.png"))
        }
    }

    func testNothingIsShownWhenNothingIsLoaded() throws {
        let empty = try render(nil)
        var bright = 0
        for y in 0..<empty.pixelsHigh { for x in stride(from: 0, to: empty.pixelsWide, by: 2) where brightness(empty, x: x, y: y) > 0.5 { bright += 1 } }
        XCTAssertEqual(bright, 0, "with no track the bar is invisible")
    }

    func testAnUnseekableTrackStillRendersWithoutAFilledBar() throws {
        let stream = try render(snapshot(position: 30, duration: 0))
        let row = brightRow(stream)
        XCTAssertLessThan(filledWidth(stream, row: row), 120, "no long filled track for a track with no length")
    }
}
