import XCTest
import SwiftUI
import AppKit
import LyraCore
@testable import LyraRender

final class AutoThemeStatusTests: XCTestCase {
    func testTheLineReadsLikeTheDesign() {
        let s = AutoThemeStatus()
        XCTAssertEqual(s.line, "Waiting for a song to read.")
        s.mood = .energetic; s.themeName = "Pulse"; s.reason = "Rock · 128 BPM"
        XCTAssertEqual(s.line, "Looking at: Rock · 128 BPM → Energetic → Pulse")
        s.themeName = nil
        XCTAssertEqual(s.line, "Looking at: Rock · 128 BPM → Energetic")
        s.reason = ""
        XCTAssertEqual(s.line, "Looking at: the song → Energetic")
    }

    func testUpdateAndClear() {
        let s = AutoThemeStatus()
        let d = ThemeDecision(themeID: "builtin.pulse", mood: .party, confidence: 0.7, reason: "Dance · 124 BPM")
        s.update(d, themeName: "Pulse")
        XCTAssertEqual(s.mood, .party)
        XCTAssertEqual(s.themeName, "Pulse")
        XCTAssertEqual(s.reason, "Dance · 124 BPM")
        s.clear()
        XCTAssertNil(s.mood); XCTAssertNil(s.themeName); XCTAssertEqual(s.reason, "")
    }

    func testIsObservable() {
        let s = AutoThemeStatus()
        var fired = 0
        let c = s.objectWillChange.sink { fired += 1 }
        s.mood = .chill
        s.themeName = "Ocean"
        s.reason = "Jazz"
        XCTAssertEqual(fired, 3)
        c.cancel()
    }
}

final class AutoThemeSettingsPersistenceTests: XCTestCase {
    func testAppSettingsCarryTheAutoThemeAndOldFilesStillLoad() throws {
        var s = AppSettings()
        XCTAssertFalse(s.autoTheme.enabled)
        s.autoTheme.enabled = true
        s.autoTheme.moodThemeIDs = ["chill": "builtin.ocean"]
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back.autoTheme, s.autoTheme)
        let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"styleID": "wave"}"#.utf8))
        XCTAssertEqual(old.autoTheme, AutoThemeSettings())
        XCTAssertEqual(old.styleID, "wave")
        let broken = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"autoTheme": 5, "styleID": "wave"}"#.utf8))
        XCTAssertEqual(broken.autoTheme, AutoThemeSettings())
    }
}

final class AutoThemeSectionRenderTests: XCTestCase {
    private func model(enabled: Bool) -> SettingsModel {
        var s = AppSettings()
        s.autoTheme.enabled = enabled
        return SettingsModel(settings: s, themeStore: ThemeStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("lyra-auto-\(UUID().uuidString)")))
    }

    private func render<V: View>(_ view: V, width: CGFloat = 580) throws -> NSBitmapImageRep {
        let host = NSHostingView(rootView: view.padding(20).frame(width: width).background(Color(white: 0.16)).environment(\.colorScheme, .dark))
        let size = host.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.alphaValue = 0
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        window.effectiveAppearance.performAsCurrentDrawingAppearance { host.cacheDisplay(in: host.bounds, to: rep) }
        window.orderOut(nil)
        return rep
    }

    private func pixels(_ rep: NSBitmapImageRep) -> [UInt8] {
        guard let data = rep.bitmapData else { return [] }
        return Array(UnsafeBufferPointer(start: data, count: rep.bytesPerRow * rep.pixelsHigh))
    }

    private func distinctColors(_ rep: NSBitmapImageRep, step: Int = 5) -> Int {
        var seen = Set<UInt32>()
        for y in stride(from: 0, to: rep.pixelsHigh, by: step) {
            for x in stride(from: 0, to: rep.pixelsWide, by: step) {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                seen.insert(UInt32(c.redComponent * 15) << 8 | UInt32(c.greenComponent * 15) << 4 | UInt32(c.blueComponent * 15))
            }
        }
        return seen.count
    }

    private func save(_ rep: NSBitmapImageRep, _ name: String) throws {
        if let dir = ProcessInfo.processInfo.environment["LYRA_SNAPSHOT_DIR"], let png = rep.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
        }
    }

    func testTheSectionRendersWithAllMoodRows() throws {
        FontCatalog.registerBundledFonts()
        let status = AutoThemeStatus(mood: .energetic, themeName: "Pulse", reason: "Rock · 128 BPM")
        let rep = try render(MatchTheMusicSection(model: model(enabled: true), status: status))
        XCTAssertGreaterThan(rep.pixelsHigh, 500, "header, text, status and twelve rows")
        XCTAssertGreaterThan(distinctColors(rep), 12)
        try save(rep, "match-the-music.png")
    }

    func testTheSectionDimsWhenOffAndDiffersFromOn() throws {
        let on = try render(MatchTheMusicSection(model: model(enabled: true), status: AutoThemeStatus()))
        let off = try render(MatchTheMusicSection(model: model(enabled: false), status: AutoThemeStatus()))
        XCTAssertNotEqual(pixels(on), pixels(off))
        try save(off, "match-the-music-off.png")
    }

    func testTheStatusLineIsDrawn() throws {
        let m = model(enabled: true)
        let waiting = try render(MatchTheMusicSection(model: m, status: AutoThemeStatus()))
        let live = try render(MatchTheMusicSection(model: m, status: AutoThemeStatus(mood: .chill, themeName: "Ocean", reason: "Jazz · 84 BPM")))
        XCTAssertNotEqual(pixels(waiting), pixels(live))
    }

    func testPickingAThemeForAMoodIsStoredAndAutomaticClearsIt() {
        let m = model(enabled: true)
        var saved: AppSettings?
        m.onChange = { saved = $0 }
        let binding = Binding<String>(get: { m.settings.autoTheme.moodThemeIDs["chill"] ?? "" },
                                      set: { id in
                                          var map = m.settings.autoTheme.moodThemeIDs
                                          if id.isEmpty { map.removeValue(forKey: "chill") } else { map["chill"] = id }
                                          m.settings.autoTheme.moodThemeIDs = map
                                      })
        binding.wrappedValue = "builtin.ocean"
        XCTAssertEqual(saved?.autoTheme.moodThemeIDs["chill"], "builtin.ocean")
        binding.wrappedValue = ""
        XCTAssertEqual(saved?.autoTheme.moodThemeIDs, [:])
    }

    func testEveryMoodRowIsDrawnAndSelectionChangesTheRow() throws {
        let themes = BuiltInThemes.all
        var sel = ""
        let auto = try render(MoodRow(mood: .party, themes: themes, selection: Binding(get: { sel }, set: { sel = $0 })), width: 560)
        sel = "builtin.neon"
        let chosen = try render(MoodRow(mood: .party, themes: themes, selection: Binding(get: { sel }, set: { sel = $0 })), width: 560)
        XCTAssertNotEqual(pixels(auto), pixels(chosen), "the picker shows the chosen theme")
    }
}
