import XCTest
@testable import LyraCore

final class GenreClassifierTests: XCTestCase {
    /// Real-world tags as Apple Music, Spotify playlists and file metadata spell them.
    private let table: [(String, Mood)] = [
        ("Rock", .energetic), ("Alternative Rock", .energetic), ("Indie Rock", .energetic), ("Pop/Rock", .energetic),
        ("Hip-Hop/Rap", .energetic), ("Hip Hop", .energetic), ("Rap", .energetic), ("Electronic", .energetic),
        ("Drum & Bass", .energetic), ("Drum and Bass", .energetic), ("Dubstep", .energetic), ("Pop Punk", .energetic),
        ("Heavy Metal", .aggressive), ("Metal", .aggressive), ("Thrash Metal", .aggressive), ("Death Metal", .aggressive),
        ("Hardcore", .aggressive), ("Metalcore", .aggressive), ("Punk", .aggressive), ("Hard Rock", .aggressive),
        ("Industrial", .aggressive), ("Grime", .aggressive), ("Drill", .aggressive), ("Trap", .aggressive),
        ("Dance", .party), ("House", .party), ("EDM", .party), ("Disco", .party), ("Reggaeton", .party),
        ("Techno", .party), ("Trance", .party), ("Dancehall", .party), ("Salsa", .party), ("Latin", .party),
        ("K-Pop", .party), ("Funk", .party), ("Afrobeats", .party), ("Samba", .party), ("Música Latina", .party),
        ("R&B/Soul", .romantic), ("R&B", .romantic), ("Soul", .romantic), ("Love Songs", .romantic),
        ("Ballads", .romantic), ("Quiet Storm", .romantic), ("Bolero", .romantic), ("Tango", .romantic),
        ("Soft Rock", .romantic), ("Adult Contemporary", .romantic), ("Vocal Jazz", .romantic),
        ("Lo-Fi", .chill), ("Lofi Hip Hop", .chill), ("Chillout", .chill), ("Smooth Jazz", .chill), ("Reggae", .chill),
        ("Jazz", .chill), ("Bossa Nova", .chill), ("Lounge", .chill), ("Downtempo", .chill), ("Relaxation", .chill),
        ("Meditation", .chill), ("Yacht Rock", .chill),
        ("Ambient", .dreamy), ("Dream Pop", .dreamy), ("Shoegaze", .dreamy), ("New Age", .dreamy),
        ("Indie", .dreamy), ("Psychedelic Rock", .dreamy), ("Chillwave", .dreamy), ("Neoclassical", .dreamy),
        ("Blues", .melancholic), ("Emo", .melancholic), ("Sad Songs", .melancholic), ("Fado", .melancholic),
        ("Slowcore", .melancholic), ("Alternative", .melancholic),
        ("Gothic", .dark), ("Darkwave", .dark), ("Doom Metal", .dark), ("Black Metal", .dark), ("Trip Hop", .dark),
        ("Post-Punk", .dark), ("Grunge", .dark), ("Dark Ambient", .dark),
        ("Classical", .epic), ("Soundtrack", .epic), ("Orchestral", .epic), ("Opera", .epic), ("Film Score", .epic),
        ("Score", .epic), ("Symphonic Metal", .epic), ("Power Metal", .epic), ("Gospel", .epic), ("Progressive Rock", .epic),
        ("Synthwave", .retro), ("Oldies", .retro), ("New Wave", .retro), ("Synth-Pop", .retro), ("Doo-Wop", .retro),
        ("Swing", .retro), ("Big Band", .retro), ("Classic Rock", .retro), ("Rockabilly", .retro), ("City Pop", .retro),
        ("Vaporwave", .retro), ("80s", .retro),
        ("Folk", .acoustic), ("Singer/Songwriter", .acoustic), ("Country", .acoustic), ("Bluegrass", .acoustic),
        ("Acoustic", .acoustic), ("Americana", .acoustic), ("Unplugged", .acoustic), ("Folk Rock", .acoustic),
        ("Celtic", .acoustic), ("Alternative Country", .acoustic), ("Christian", .acoustic),
        ("Pop", .playful), ("Children's Music", .playful), ("Kids", .playful), ("Ska", .playful), ("J-Pop", .playful),
        ("Anime", .playful), ("Holiday", .playful), ("Christmas", .playful), ("Comedy", .playful), ("Disney", .playful),
        ("Bollywood", .playful), ("Show Tunes", .playful), ("Chiptune", .playful), ("Teen Pop", .playful),
    ]

    func testTheTableHasAtLeastEightyRealWorldStrings() {
        XCTAssertGreaterThanOrEqual(table.count, 80)
        XCTAssertEqual(Set(table.map(\.0)).count, table.count, "no duplicates")
    }

    func testEveryStringMapsToItsMood() {
        var failures: [String] = []
        for (genre, mood) in table {
            let got = GenreClassifier.classify(genre)?.mood
            if got != mood { failures.append("\(genre): expected \(mood) got \(got.map { "\($0)" } ?? "nil")") }
        }
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }

    func testEveryMoodExceptNeutralIsReachableFromGenres() {
        let reached = Set(table.map(\.1))
        for m in Mood.selectable { XCTAssertTrue(reached.contains(m), "\(m) has no genre in the table") }
    }

    func testCaseAndDiacriticsDontMatter() {
        for variant in ["ROCK", "rock", "RoCk", "  rock  "] { XCTAssertEqual(GenreClassifier.classify(variant)?.mood, .energetic, variant) }
        XCTAssertEqual(GenreClassifier.classify("Música Clásica")?.mood, .epic)
        XCTAssertEqual(GenreClassifier.classify("musica clasica")?.mood, .epic)
        XCTAssertEqual(GenreClassifier.classify("Électronique")?.mood, GenreClassifier.classify("Electronique")?.mood)
        XCTAssertEqual(GenreClassifier.classify("Música Latina")?.mood, GenreClassifier.classify("Musica Latina")?.mood)
        XCTAssertEqual(GenreClassifier.classify("Lo-Fi")?.mood, GenreClassifier.classify("lo fi")?.mood)
        XCTAssertEqual(GenreClassifier.classify("Lo-Fi")?.mood, GenreClassifier.classify("LOFI")?.mood)
    }

    func testLocalizedWordsAreBestEffort() {
        XCTAssertEqual(GenreClassifier.classify("Klassik")?.mood, .epic)
        XCTAssertEqual(GenreClassifier.classify("Música Clásica")?.mood, .epic)
        XCTAssertEqual(GenreClassifier.classify("Musique Classique")?.mood, .epic)
        XCTAssertEqual(GenreClassifier.classify("Tanz")?.mood, .party)
        XCTAssertEqual(GenreClassifier.classify("Kinderlieder")?.mood, .playful)
        XCTAssertEqual(GenreClassifier.classify("Weihnachten")?.mood, .playful)
        XCTAssertEqual(GenreClassifier.classify("Rap Français")?.mood, .energetic)
    }

    func testSeparatorsAndMultipleGenres() {
        XCTAssertEqual(GenreClassifier.classify("Rock, Alternative")?.mood, .energetic, "the first genre is the primary one")
        XCTAssertEqual(GenreClassifier.classify("Metal; Rock")?.mood, .aggressive)
        XCTAssertEqual(GenreClassifier.classify("Dance | Electronic")?.mood, .party)
        XCTAssertEqual(GenreClassifier.classify("Hip-Hop/Rap, R&B/Soul")?.mood, .energetic)
        XCTAssertEqual(GenreClassifier.classify("Pop / Dance")?.mood, .party, "a stronger rule outvotes a weak one")
    }

    func testMostSpecificRuleWins() {
        XCTAssertEqual(GenreClassifier.classify("Doom Metal")?.mood, .dark)
        XCTAssertEqual(GenreClassifier.classify("Power Metal")?.mood, .epic)
        XCTAssertEqual(GenreClassifier.classify("Hard Rock")?.mood, .aggressive)
        XCTAssertEqual(GenreClassifier.classify("Soft Rock")?.mood, .romantic)
        XCTAssertEqual(GenreClassifier.classify("Alternative Country")?.mood, .acoustic)
        XCTAssertEqual(GenreClassifier.classify("Dream Pop")?.mood, .dreamy)
        XCTAssertEqual(GenreClassifier.classify("Pop Punk")?.mood, .energetic)
    }

    func testTagsThatSayNothingGiveNil() {
        for g in ["", "   ", "Music", "Unknown", "Other", "World", "Various", "Genres", "///", "12345", "Qwertyuiop", "—"] {
            XCTAssertNil(GenreClassifier.classify(g), g)
        }
    }

    func testConfidenceIsBoundedAndReflectsSpecificity() throws {
        for (genre, _) in table {
            let c = try XCTUnwrap(GenreClassifier.classify(genre)).confidence
            XCTAssertTrue((0.3...0.95).contains(c), "\(genre) \(c)")
        }
        let lofi = try XCTUnwrap(GenreClassifier.classify("Lo-Fi")).confidence
        let pop = try XCTUnwrap(GenreClassifier.classify("Pop")).confidence
        XCTAssertGreaterThan(lofi, pop, "a generic tag says less than a specific one")
        let mixed = try XCTUnwrap(GenreClassifier.classify("Metal/Folk")).confidence
        let pure = try XCTUnwrap(GenreClassifier.classify("Metal")).confidence
        XCTAssertLessThan(mixed, pure, "a tag that disagrees with itself is less certain")
    }

    func testNormalization() {
        XCTAssertEqual(GenreClassifier.normalize("Hip-Hop/Rap"), "hip hop rap")
        XCTAssertEqual(GenreClassifier.normalize("R&B/Soul"), "r and b soul")
        XCTAssertEqual(GenreClassifier.normalize("  Música   Clásica!! "), "musica clasica")
        XCTAssertEqual(GenreClassifier.normalize("日本"), "日本")
        XCTAssertEqual(GenreClassifier.segments(of: "a, b / c;d").count, 4)
        XCTAssertEqual(GenreClassifier.segments(of: " , / ").count, 0)
    }

    func testAllRulesAreWellFormed() {
        XCTAssertGreaterThan(GenreClassifier.ruleCount, 300)
    }
}
