import XCTest
@testable import LyraCore

private func track(_ id: String, genre: String = "", duration: TimeInterval = 200) -> Track {
    Track(title: "Sample \(id)", artist: "Invented Artist", album: "Album", duration: duration, player: .appleMusic, genre: genre, id: id)
}

private func palette(_ dominant: RGBA, accent: RGBA, dark: Bool) -> Palette {
    Palette(dominant: dominant, accent: accent, secondary: accent, swatches: [dominant, accent], isDark: dark)
}

private let warmCover = palette(RGBA(0.95, 0.6, 0.2), accent: RGBA(1, 0.65, 0.1), dark: false)       // playful
private let coolCover = palette(RGBA(0.2, 0.5, 0.8), accent: RGBA(0.1, 0.6, 0.95), dark: false)      // chill
private let darkCover = palette(RGBA(0.05, 0.05, 0.07), accent: RGBA(0.3, 0.3, 0.35), dark: true)    // dark

private func tick(level: Float = 0.5, bass: Float = 0.5, mid: Float = 0.5, treble: Float = 0.5, bpm: Double? = nil,
                  brightness: Float = 0.5, energy: Float = 0.5) -> AudioFeatures {
    AudioFeatures(level: level, bass: bass, mid: mid, treble: treble, beat: 0, bpm: bpm, brightness: brightness, energy: energy)
}

private let calmTick = tick(level: 0.15, bass: 0.3, mid: 0.4, treble: 0.3, bpm: 62, brightness: 0.15, energy: 0.15)
private let fastTick = tick(level: 0.8, bass: 0.35, mid: 0.4, treble: 0.4, bpm: 150, brightness: 0.7, energy: 0.75)

private func enabledSettings() -> AutoThemeSettings {
    var s = AutoThemeSettings()
    s.enabled = true
    return s
}

private func makeEngine(_ s: AutoThemeSettings? = nil) -> AutoThemeEngine {
    AutoThemeEngine(settings: s ?? enabledSettings(), themeIDs: BuiltInThemes.all.map(\.id))
}

/// Feeds an engine audio at 10 Hz until `seconds` pass (starting at `from`); returns the first decision and the time.
@discardableResult
private func listen(_ e: AutoThemeEngine, _ f: AudioFeatures, from: Double, seconds: Double) -> (ThemeDecision?, Double) {
    var t = from
    var first: ThemeDecision?
    while t <= from + seconds {
        if let d = e.audio(features: f, now: t), first == nil { first = d }
        t += 0.1
    }
    return (first, t)
}

// MARK: - Mapping

final class MoodThemeMappingTests: XCTestCase {
    func testEveryMappedIDExistsInTheBuiltInThemes() {
        let ids = Set(BuiltInThemes.all.map(\.id))
        for (mood, list) in MoodThemes.defaults {
            for id in list { XCTAssertTrue(ids.contains(id), "\(mood.rawValue) refers to \(id), which is not a built-in theme") }
        }
    }

    func testEveryMoodHasAtLeastThreeDistinctThemes() {
        for mood in Mood.allCases {
            let list = MoodThemes.defaults[mood] ?? []
            XCTAssertGreaterThanOrEqual(Set(list).count, 3, mood.rawValue)
            XCTAssertEqual(Set(list).count, list.count, "\(mood.rawValue) lists a theme twice")
        }
    }

    func testTheMappingMakesMusicalSense() {
        let d = MoodThemes.defaults
        // Metal-looking themes for aggressive.
        XCTAssertTrue(d[.aggressive]!.contains("builtin.forge"))
        XCTAssertTrue(d[.aggressive]!.contains("builtin.katana"))
        XCTAssertTrue(d[.aggressive]!.contains("builtin.thorn"))
        // Soft handwriting or serif for romantic.
        XCTAssertTrue(d[.romantic]!.contains("builtin.diary"))
        XCTAssertTrue(d[.romantic]!.contains("builtin.elegant"))
        // Neon and synthwave for energetic and retro.
        XCTAssertTrue(d[.energetic]!.contains("builtin.neon"))
        XCTAssertTrue(d[.retro]!.contains("builtin.retro-wave"))
        XCTAssertTrue(d[.retro]!.contains("builtin.neon"))
        // Typewriter or minimal for acoustic and chill.
        XCTAssertTrue(d[.acoustic]!.contains("builtin.newsprint"))
        XCTAssertTrue(d[.chill]!.contains("builtin.minimal"))
        // Cathedral for dark and epic, cinema for epic.
        XCTAssertTrue(d[.dark]!.contains("builtin.cathedral"))
        XCTAssertTrue(d[.epic]!.contains("builtin.cinema"))
    }

    func testMapsHoldNoBogusKeysWhenMoodsGrow() {
        XCTAssertEqual(Set(MoodThemes.defaults.keys), Set(Mood.allCases))
    }
}

// MARK: - Picking

final class MoodThemePickTests: XCTestCase {
    private let ids = BuiltInThemes.all.map(\.id)
    private func pick(_ mood: Mood, _ key: String, active: String? = nil, _ s: AutoThemeSettings = AutoThemeSettings()) -> String? {
        MoodThemes.pick(mood: mood, trackKey: key, activeThemeID: active, settings: s, knownThemeIDs: ids)
    }

    func testTheSameTrackAlwaysGetsTheSameTheme() {
        for key in ["id:a", "id:b", "t:x|y|z"] {
            let first = pick(.energetic, key)
            for _ in 0..<5 { XCTAssertEqual(pick(.energetic, key), first) }
        }
    }

    func testDifferentTracksSpreadAcrossTheMoodsThemes() {
        let picks = Set((0..<60).compactMap { pick(.energetic, "id:\($0)") })
        XCTAssertGreaterThanOrEqual(picks.count, 4, "\(picks)")
        XCTAssertTrue(picks.isSubset(of: Set(MoodThemes.defaults[.energetic]!)))
    }

    func testTheActiveThemeIsAvoidedSoConsecutiveSongsVary() {
        for i in 0..<40 {
            let key = "id:\(i)"
            let natural = pick(.chill, key)!
            let avoiding = pick(.chill, key, active: natural)!
            XCTAssertNotEqual(avoiding, natural)
            XCTAssertTrue(MoodThemes.defaults[.chill]!.contains(avoiding))
        }
    }

    func testAMoodOverrideWinsWhenTheThemeExists() {
        var s = AutoThemeSettings()
        s.moodThemeIDs[Mood.chill.rawValue] = "builtin.forge"
        XCTAssertEqual(pick(.chill, "id:1", s), "builtin.forge")
        XCTAssertEqual(pick(.chill, "id:2", active: "builtin.forge", s), "builtin.forge", "an explicit choice is not varied")
        XCTAssertNotEqual(pick(.party, "id:1", s), "builtin.forge", "other moods are unaffected")
    }

    func testAnOverrideToAMissingThemeIsIgnored() {
        var s = AutoThemeSettings()
        s.moodThemeIDs[Mood.chill.rawValue] = "builtin.does-not-exist"
        s.moodThemeIDs["not-a-mood"] = "builtin.forge"
        let p = pick(.chill, "id:1", s)
        XCTAssertTrue(MoodThemes.defaults[.chill]!.contains(p!))
    }

    func testFavoritesRestrictTheChoice() {
        var s = AutoThemeSettings()
        s.onlyThemeIDs = ["builtin.ocean", "builtin.forest", "builtin.forge"]
        for i in 0..<30 {
            let p = pick(.chill, "id:\(i)", s)!
            XCTAssertTrue(["builtin.ocean", "builtin.forest"].contains(p), "chill ∩ favorites only: \(p)")
        }
    }

    func testFavoritesWithNoOverlapFallBackToAnyFavorite() {
        var s = AutoThemeSettings()
        s.onlyThemeIDs = ["builtin.forge", "builtin.katana"]
        for i in 0..<20 { XCTAssertTrue(s.onlyThemeIDs.contains(pick(.romantic, "id:\(i)", s)!)) }
    }

    func testFavoritesOfUnknownThemesAreIgnoredAndAnEmptyListMeansNoRestriction() {
        var s = AutoThemeSettings()
        s.onlyThemeIDs = ["builtin.nope", "custom.gone"]
        XCTAssertTrue(MoodThemes.defaults[.epic]!.contains(pick(.epic, "id:1", s)!))
        s.onlyThemeIDs = []
        XCTAssertTrue(MoodThemes.defaults[.epic]!.contains(pick(.epic, "id:1", s)!))
    }

    func testAnOverrideBeatsFavorites() {
        var s = AutoThemeSettings()
        s.onlyThemeIDs = ["builtin.ocean"]
        s.moodThemeIDs[Mood.chill.rawValue] = "builtin.forge"
        XCTAssertEqual(pick(.chill, "id:1", s), "builtin.forge")
    }

    func testNothingKnownMeansNil() {
        XCTAssertNil(MoodThemes.pick(mood: .chill, trackKey: "k", activeThemeID: nil, settings: AutoThemeSettings(), knownThemeIDs: []))
    }

    func testTheHashIsStable() {
        // FNV-1a test vectors, so a launch never changes a song's look.
        XCTAssertEqual(MoodThemes.stableHash(""), 0xcbf29ce484222325)
        XCTAssertEqual(MoodThemes.stableHash("a"), 0xaf63dc4c8601ec8c)
        XCTAssertEqual(MoodThemes.stableHash("foobar"), 0x85944171f73967e8)
    }
}

// MARK: - Settings

final class AutoThemeSettingsTests: XCTestCase {
    func testDefaultsAreOptInWithEverySignalOn() {
        let s = AutoThemeSettings()
        XCTAssertFalse(s.enabled)
        XCTAssertTrue(s.useGenre && s.useAudio && s.useCover)
        XCTAssertTrue(s.moodThemeIDs.isEmpty)
        XCTAssertTrue(s.onlyThemeIDs.isEmpty)
        XCTAssertTrue(s.usesAnySignal)
    }

    func testRoundTrips() throws {
        var s = AutoThemeSettings()
        s.enabled = true
        s.useAudio = false
        s.moodThemeIDs = ["chill": "builtin.ocean"]
        s.onlyThemeIDs = ["builtin.ocean", "builtin.forge"]
        let back = try JSONDecoder().decode(AutoThemeSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back, s)
    }

    func testDecodingIsTolerant() throws {
        func decode(_ json: String) throws -> AutoThemeSettings { try JSONDecoder().decode(AutoThemeSettings.self, from: Data(json.utf8)) }
        XCTAssertEqual(try decode("{}"), AutoThemeSettings())
        let partial = try decode(#"{"enabled": true, "useGenre": false}"#)
        XCTAssertTrue(partial.enabled)
        XCTAssertFalse(partial.useGenre)
        XCTAssertTrue(partial.useAudio)
        let wrong = try decode(#"{"enabled": "yes", "moodThemeIDs": [1,2], "onlyThemeIDs": {"a": 1}, "useCover": false, "future": 7}"#)
        XCTAssertFalse(wrong.enabled, "malformed values keep their defaults")
        XCTAssertTrue(wrong.moodThemeIDs.isEmpty)
        XCTAssertTrue(wrong.onlyThemeIDs.isEmpty)
        XCTAssertFalse(wrong.useCover, "valid neighbours still load")
    }
}

// MARK: - Engine

final class AutoThemeEngineTests: XCTestCase {
    func testDisabledNeverDecidesAndNeverHoldsState() {
        let e = makeEngine(AutoThemeSettings())
        XCTAssertNil(e.trackChanged(track: track("1", genre: "Metal"), palette: darkCover, now: 0))
        XCTAssertNil(e.audio(features: fastTick, now: 1))
        XCTAssertNil(e.palette(coolCover, now: 2))
    }

    func testDecidesImmediatelyAtTrackStartFromGenre() throws {
        let e = makeEngine()
        let d = try XCTUnwrap(e.trackChanged(track: track("1", genre: "Heavy Metal"), palette: nil, now: 0))
        XCTAssertEqual(d.mood, .aggressive)
        XCTAssertEqual(d.stage, .initial)
        XCTAssertTrue(MoodThemes.defaults[.aggressive]!.contains(d.themeID))
        XCTAssertTrue(d.reason.contains("Heavy Metal"))
        XCTAssertGreaterThan(d.confidence, 0.5)
        XCTAssertEqual(e.activeThemeID, d.themeID)
        XCTAssertEqual(e.changesThisTrack, 1)
    }

    func testDecidesFromTheCoverWhenThereIsNoGenre() throws {
        let e = makeEngine()
        let d = try XCTUnwrap(e.trackChanged(track: track("1"), palette: warmCover, now: 0))
        XCTAssertEqual(d.mood, .playful)
        XCTAssertTrue(d.reason.contains("cover"))
    }

    func testNoEvidenceMeansNoChange() {
        let e = makeEngine()
        XCTAssertNil(e.trackChanged(track: track("1"), palette: nil, now: 0))
        XCTAssertNil(e.trackChanged(track: track("2", genre: "Qwerty"), palette: nil, now: 1))
        XCTAssertNil(e.trackChanged(track: nil, palette: nil, now: 2))
    }

    func testSignalSwitchesAreHonored() {
        var s = enabledSettings()
        s.useGenre = false
        XCTAssertNil(makeEngine(s).trackChanged(track: track("1", genre: "Metal"), palette: nil, now: 0), "genre switched off, nothing else known")
        s = enabledSettings(); s.useCover = false
        XCTAssertNil(makeEngine(s).trackChanged(track: track("1"), palette: warmCover, now: 0))
        s = enabledSettings(); s.useAudio = false
        let e = makeEngine(s)
        _ = e.trackChanged(track: track("1"), palette: nil, now: 0)
        XCTAssertNil(listen(e, fastTick, from: 0, seconds: 30).0)
    }

    func testAllSignalsOffNeverDecides() {
        var s = enabledSettings()
        s.useGenre = false; s.useAudio = false; s.useCover = false
        XCTAssertNil(makeEngine(s).trackChanged(track: track("1", genre: "Metal"), palette: darkCover, now: 0))
    }

    func testTheSameTrackReportedAgainIsIgnored() {
        let e = makeEngine()
        XCTAssertNotNil(e.trackChanged(track: track("1", genre: "Rock"), palette: nil, now: 0))
        XCTAssertNil(e.trackChanged(track: track("1", genre: "Rock"), palette: nil, now: 5))
        XCTAssertEqual(e.changesThisTrack, 1)
    }

    func testTheCoverArrivingLaterAllowsOneCheapRedecision() throws {
        let e = makeEngine()
        XCTAssertNil(e.trackChanged(track: track("1"), palette: nil, now: 0), "no genre, no cover yet")
        let d = try XCTUnwrap(e.palette(coolCover, now: 1.5))
        XCTAssertEqual(d.mood, .chill)
        XCTAssertEqual(d.stage, .cover)
        // A second, different cover does not trigger anything more.
        XCTAssertNil(e.palette(warmCover, now: 2))
    }

    func testALateCoverIsOnlyStoredNotActedOn() {
        let e = makeEngine()
        _ = e.trackChanged(track: track("1"), palette: nil, now: 0)
        XCTAssertNil(e.palette(coolCover, now: 60), "past the settle window")
        XCTAssertEqual(e.changesThisTrack, 0)
    }

    func testAContradictingCoverDoesNotOverturnAConfidentGenre() {
        let e = makeEngine()
        XCTAssertNotNil(e.trackChanged(track: track("1", genre: "Heavy Metal"), palette: nil, now: 0))
        XCTAssertNil(e.palette(warmCover, now: 1))
        XCTAssertEqual(e.changesThisTrack, 1)
    }

    func testAudioRefinesOnceWhenItDisagreesStronglyWithAWeakEarlyGuess() throws {
        let e = makeEngine()
        let early = try XCTUnwrap(e.trackChanged(track: track("1", genre: "Pop"), palette: nil, now: 0))
        XCTAssertEqual(early.mood, .playful)
        XCTAssertNil(listen(e, calmTick, from: 0.1, seconds: 8).0, "not before 12 s of audio")
        let (refined, t) = listen(e, calmTick, from: 8.2, seconds: 8)
        let d = try XCTUnwrap(refined)
        XCTAssertEqual(d.stage, .audio)
        XCTAssertEqual(d.mood, .melancholic)
        XCTAssertNotEqual(d.themeID, early.themeID)
        XCTAssertTrue(d.reason.contains("62 BPM"), d.reason)
        XCTAssertEqual(e.changesThisTrack, 2)
        // Never again, whatever the audio does.
        XCTAssertNil(listen(e, fastTick, from: t, seconds: 40).0)
        XCTAssertEqual(e.changesThisTrack, 2)
    }

    func testAudioAgreeingWithTheEarlyGuessChangesNothing() {
        let e = makeEngine()
        XCTAssertNotNil(e.trackChanged(track: track("1", genre: "Rock"), palette: nil, now: 0))
        XCTAssertNil(listen(e, fastTick, from: 0.1, seconds: 20).0)
        XCTAssertEqual(e.changesThisTrack, 1)
    }

    func testAConfidentGenreIsNotOverturnedByAudio() {
        let e = makeEngine()
        XCTAssertNotNil(e.trackChanged(track: track("1", genre: "Heavy Metal"), palette: nil, now: 0))
        XCTAssertNil(listen(e, calmTick, from: 0.1, seconds: 30).0)
    }

    func testAudioIsTheFirstDecisionWhenNothingElseIsKnown() throws {
        let e = makeEngine()
        XCTAssertNil(e.trackChanged(track: track("1"), palette: nil, now: 0))
        let d = try XCTUnwrap(listen(e, fastTick, from: 0.1, seconds: 20).0)
        XCTAssertEqual(d.mood, .energetic)
    }

    func testAudioIsEvaluatedExactlyOncePerTrackEvenWhenItChangesNothing() {
        let e = makeEngine()
        _ = e.trackChanged(track: track("1", genre: "Rock"), palette: nil, now: 0)
        let (_, t) = listen(e, fastTick, from: 0.1, seconds: 15)   // agrees: evaluated, no change
        XCTAssertNil(listen(e, calmTick, from: t, seconds: 60).0, "a later disagreement is not a second chance")
    }

    func testNeverMoreThanTwoChangesPerTrack() {
        let e = makeEngine()
        var changes = 0
        if e.trackChanged(track: track("1"), palette: nil, now: 0) != nil { changes += 1 }
        if e.palette(coolCover, now: 1) != nil { changes += 1 }
        if listen(e, calmTick, from: 1.1, seconds: 30).0 != nil { changes += 1 }
        if e.palette(darkCover, now: 40) != nil { changes += 1 }
        XCTAssertLessThanOrEqual(changes, 2)
        XCTAssertEqual(e.changesThisTrack, changes)
    }

    func testNeverFlipsBackAndForthAcrossManySimulatedTracks() {
        let e = makeEngine()
        var t = 0.0
        for n in 0..<60 {
            let genre = ["Pop", "", "Rock", "Jazz"][n % 4]
            var decisions = 0
            if e.trackChanged(track: track("t\(n)", genre: genre), palette: n % 2 == 0 ? warmCover : nil, now: t) != nil { decisions += 1 }
            if e.palette(n % 3 == 0 ? coolCover : darkCover, now: t + 1) != nil { decisions += 1 }
            let (d, end) = listen(e, n % 2 == 0 ? calmTick : fastTick, from: t + 1.1, seconds: 20)
            if d != nil { decisions += 1 }
            XCTAssertLessThanOrEqual(decisions, 2, "track \(n)")
            t = end + 1
        }
    }

    func testNoAutomaticChangeInTheLastSecondsOfATrack() {
        let e = makeEngine()
        _ = e.trackChanged(track: track("1", genre: "Pop", duration: 20), palette: nil, now: 0)
        // Audio is ready at 12 s; the track ends at 20 s: inside the 10 s end guard.
        XCTAssertNil(listen(e, calmTick, from: 0.1, seconds: 19).0)
        XCTAssertEqual(e.changesThisTrack, 1)
    }

    func testTheEndGuardUsesTheReportedPositionWhenGiven() throws {
        let e = makeEngine()
        _ = e.trackChanged(track: track("1", genre: "Pop", duration: 100), palette: nil, now: 0)
        var t = 0.1
        var got: ThemeDecision?
        while t < 20 { if let d = e.audio(features: calmTick, now: t, position: 95) { got = d }; t += 0.1 }
        XCTAssertNil(got, "position 95 of 100 is inside the guard")
    }

    func testUserChoiceSuppressesAutoChangesUntilTheNextTrack() throws {
        let e = makeEngine()
        _ = e.trackChanged(track: track("1", genre: "Pop"), palette: nil, now: 0)
        e.userChoseTheme(now: 3)
        XCTAssertNil(listen(e, calmTick, from: 3.1, seconds: 30).0)
        XCTAssertNil(e.palette(coolCover, now: 4))
        XCTAssertEqual(e.changesThisTrack, 1)
        // The next track is free again.
        XCTAssertNotNil(e.trackChanged(track: track("2", genre: "Heavy Metal"), palette: nil, now: 100))
    }

    func testUserChoiceBeforeTheInitialDecisionOnlyCoversTheCurrentTrack() {
        let e = makeEngine()
        _ = e.trackChanged(track: track("1"), palette: nil, now: 0)
        e.userChoseTheme(now: 0.5)
        XCTAssertNil(e.palette(coolCover, now: 1))
    }

    func testTrackChangeResetsEverything() throws {
        let e = makeEngine()
        _ = e.trackChanged(track: track("1", genre: "Pop"), palette: nil, now: 0)
        _ = listen(e, calmTick, from: 0.1, seconds: 15)
        XCTAssertEqual(e.changesThisTrack, 2)
        let d = try XCTUnwrap(e.trackChanged(track: track("2", genre: "Heavy Metal"), palette: nil, now: 100))
        XCTAssertEqual(e.changesThisTrack, 1)
        XCTAssertEqual(d.mood, .aggressive)
        XCTAssertNil(e.lastDecision.flatMap { $0.mood == .melancholic ? $0 : nil })
        // Audio starts counting from zero again: 8 s is not enough.
        XCTAssertNil(listen(e, calmTick, from: 100.1, seconds: 8).0)
    }

    func testSameTrackSameLookAcrossEngineInstances() throws {
        let a = try XCTUnwrap(makeEngine().trackChanged(track: track("song-42", genre: "Rock"), palette: nil, now: 0))
        let b = try XCTUnwrap(makeEngine().trackChanged(track: track("song-42", genre: "Rock"), palette: nil, now: 999))
        XCTAssertEqual(a.themeID, b.themeID)
    }

    func testConsecutiveSongsOfOneMoodVaryBecauseTheActiveThemeIsAvoided() {
        let e = makeEngine()
        var previous: String?
        for n in 0..<25 {
            guard let d = e.trackChanged(track: track("rock-\(n)", genre: "Rock"), palette: nil, now: Double(n) * 300) else {
                XCTFail("every rock song should get a (different) theme"); continue
            }
            XCTAssertNotEqual(d.themeID, previous)
            previous = d.themeID
        }
    }

    func testOverridesAndFavoritesApplyThroughTheEngine() throws {
        var s = enabledSettings()
        s.moodThemeIDs[Mood.aggressive.rawValue] = "builtin.ocean"
        var e = makeEngine(s)
        XCTAssertEqual(e.trackChanged(track: track("1", genre: "Metal"), palette: nil, now: 0)?.themeID, "builtin.ocean")
        // Same override while it is already active: the look would not change, so no decision.
        XCTAssertNil(e.trackChanged(track: track("2", genre: "Metal"), palette: nil, now: 300))

        s = enabledSettings()
        s.onlyThemeIDs = ["builtin.minimal", "builtin.studio"]
        e = makeEngine(s)
        for n in 0..<10 {
            if let d = e.trackChanged(track: track("f\(n)", genre: n % 2 == 0 ? "Metal" : "Lo-Fi"), palette: nil, now: Double(n) * 300) {
                XCTAssertTrue(s.onlyThemeIDs.contains(d.themeID), d.themeID)
            }
        }
    }

    func testSettingsCanBeChangedLive() {
        let e = makeEngine(AutoThemeSettings())
        XCTAssertNil(e.trackChanged(track: track("1", genre: "Metal"), palette: nil, now: 0))
        e.settings = enabledSettings()
        XCTAssertNotNil(e.trackChanged(track: track("2", genre: "Metal"), palette: nil, now: 10))
    }

    func testFallsBackQuietlyWhenTheMoodsThemesAreMissing() {
        let e = AutoThemeEngine(settings: enabledSettings(), themeIDs: ["custom.only"])
        XCTAssertNil(e.trackChanged(track: track("1", genre: "Metal"), palette: nil, now: 0))
    }

    func testTracksWithoutAnIDAreKeyedByArtistAndTitle() {
        var a = track("", genre: "Rock"); a.title = "One"
        var b = track("", genre: "Rock"); b.title = "Two"
        XCTAssertNotEqual(AutoThemeEngine.key(for: a), AutoThemeEngine.key(for: b))
        XCTAssertEqual(AutoThemeEngine.key(for: a), AutoThemeEngine.key(for: a))
    }

    func testLookedAtSummary() {
        XCTAssertEqual(AutoThemeEngine.lookedAt(genre: nil, audio: nil, palette: nil), "nothing yet")
        let a = AudioSummary(energy: 0.7, bassShare: 0.3, brightness: 0.5, tempo: 128, dynamics: 0.3, seconds: 20)
        XCTAssertEqual(AutoThemeEngine.lookedAt(genre: "Rock", audio: a, palette: nil), "Rock · 128 BPM · loud")
        XCTAssertEqual(AutoThemeEngine.lookedAt(genre: "Qwerty", audio: nil, palette: darkCover), "dark muted cover")
    }
}
