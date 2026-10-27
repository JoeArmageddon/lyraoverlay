// Console harness for LyraCore.
//
//   lyra-cli parse <file.lrc>                       parse an LRC file and print timing
//   lyra-cli lookup <artist> <title> [album] [sec]  fetch lyrics (cache, then LRCLIB)
//   lyra-cli watch                                  follow Spotify / Apple Music live
//   lyra-cli audio [seconds] [--backend tap|screen] show live bass/mid/treble, beats and tempo
//   lyra-cli palette                                colors from the playing track's artwork
//   lyra-cli mood [--audio SECONDS]                 the mood and theme Lyra would pick for the playing track

import Foundation
import LyraCore

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}

func usage() -> Never {
    fail("""
    usage:
      lyra-cli parse <file.lrc>
      lyra-cli lookup <artist> <title> [album] [duration-seconds]
      lyra-cli watch
      lyra-cli audio [seconds] [--backend tap|screen]
      lyra-cli palette
      lyra-cli mood [--audio SECONDS]
    """)
}

func stamp(_ t: TimeInterval) -> String {
    String(format: "%02d:%05.2f", Int(t) / 60, t.truncatingRemainder(dividingBy: 60))
}

func printDocument(_ doc: LyricsDocument, limit: Int = 40) {
    print("source=\(doc.source) synced=\(doc.isSynced) realWordTiming=\(doc.hasWordTiming) lines=\(doc.lines.count) instrumental=\(doc.instrumental)")
    for line in doc.lines.prefix(limit) {
        let marker = line.isInstrumentalGap ? "♪" : " "
        print("\(stamp(line.start)) → \(stamp(line.sungEnd)) \(marker) \(line.text)")
    }
    if doc.lines.count > limit { print("… \(doc.lines.count - limit) more lines") }
    if !doc.isSynced, let plain = doc.plainText { print("(unsynced)\n\(plain.prefix(400))") }
}

/// Latest playback state and lyrics, shared between the monitor loop and the render loop.
final class WatchState: @unchecked Sendable {
    private let lock = NSLock()
    private var _snapshot = PlaybackSnapshot.idle
    private var _cursor: LyricsCursor?
    private var _doc: LyricsDocument?
    private var _trackKey = ""

    var snapshot: PlaybackSnapshot { lock.withLock { _snapshot } }
    var cursor: LyricsCursor? { lock.withLock { _cursor } }
    var doc: LyricsDocument? { lock.withLock { _doc } }

    /// Returns true when the track changed.
    func update(_ s: PlaybackSnapshot) -> Bool {
        lock.withLock {
            _snapshot = s
            let key = s.track.map { "\($0.player.rawValue)|\($0.id)|\($0.title)|\($0.artist)" } ?? ""
            guard key != _trackKey else { return false }
            _trackKey = key
            _doc = nil
            _cursor = nil
            return true
        }
    }

    func setDocument(_ d: LyricsDocument?, forTrackKey key: String) {
        lock.withLock {
            guard key == _trackKey else { return }
            _doc = d
            _cursor = d.flatMap { $0.isSynced ? LyricsCursor(document: $0) : nil }
        }
    }

    var trackKey: String { lock.withLock { _trackKey } }
}

func render(_ state: WatchState) -> String {
    let snap = state.snapshot
    guard snap.track != nil else { return "nothing playing" }
    guard let cursor = state.cursor, let doc = state.doc else {
        return state.doc == nil ? "…looking up lyrics" : "no synced lyrics"
    }
    let t = snap.position()
    let c = cursor.state(at: t)
    guard let i = c.lineIndex else { return "\(stamp(t))  ♪" }
    let line = doc.lines[i]
    if !c.isSinging && line.isInstrumentalGap { return "\(stamp(t))  ♪" }

    // Sung words dim, current word inverse, upcoming words plain.
    var out = ""
    for (n, w) in line.words.enumerated() {
        let piece: String
        if c.isSinging, let cur = c.wordIndex {
            piece = n < cur ? "\u{1B}[2m\(w.text)\u{1B}[0m" : n == cur ? "\u{1B}[7m\(w.text)\u{1B}[0m" : w.text
        } else {
            piece = "\u{1B}[2m\(w.text)\u{1B}[0m"
        }
        out += piece + " "
    }
    return "\(stamp(t))  \(out)"
}

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { usage() }

switch command {
case "parse":
    guard args.count == 2 else { usage() }
    guard let text = try? String(contentsOfFile: args[1], encoding: .utf8) else { fail("cannot read \(args[1])") }
    guard let doc = LRCParser.parse(text) else { fail("no timestamped lines found") }
    printDocument(doc)

case "lookup":
    guard args.count >= 3 else { usage() }
    let query = TrackQuery(
        title: args[2], artist: args[1],
        album: args.count > 3 ? args[3] : "",
        duration: args.count > 4 ? Double(args[4]) ?? 0 : 0)
    let service = LyricsService()
    if let doc = await service.lyrics(for: query) { printDocument(doc) } else { print("no lyrics found") }

case "watch":
    let monitor = NowPlayingMonitor()
    monitor.onProblem = { kind, error in
        let text: String
        switch error {
        case .notAuthorized:
            text = "Automation permission denied for \(kind). Allow it in System Settings > Privacy & Security > Automation, then restart."
        case .failed(let code, let message):
            text = "Could not read \(kind): \(message) (\(code))"
        }
        FileHandle.standardError.write(Data("\n\(text)\n".utf8))
    }
    let service = LyricsService()
    let state = WatchState()

    Task {
        while true {
            let s = state.snapshot
            let text = render(state)
            print("\r\u{1B}[2K\(text)", terminator: "")
            fflush(stdout)
            _ = s
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    for await snapshot in monitor.start() {
        guard state.update(snapshot), let track = snapshot.track else { continue }
        let key = state.trackKey
        print("\r\u{1B}[2K\n♪ \(track.title) — \(track.artist)  [\(track.genre.isEmpty ? "genre n/a" : track.genre), \(Int(track.duration))s]")
        Task {
            let doc = await service.lyrics(for: TrackQuery(track: track))
            state.setDocument(doc, forTrackKey: key)
        }
    }

case "audio":
    var audioArgs = Array(args.dropFirst())
    var source = AudioCaptureSource.systemTap
    if let i = audioArgs.firstIndex(of: "--backend") {
        guard i + 1 < audioArgs.count, let chosen = AudioCaptureSource(cliName: audioArgs[i + 1]) else { fail("--backend takes tap or screen") }
        source = chosen
        audioArgs.removeSubrange(i...(i + 1))
    }
    let seconds = audioArgs.first.flatMap { Double($0) } ?? 10
    let capture = SystemAudioCapture(source: source)
    let startedAt = Date()
    capture.onStateChange = { state in
        let t = String(format: "%5.1fs", Date().timeIntervalSince(startedAt))
        FileHandle.standardError.write(Data("\r\u{1B}[2K[\(t)] state -> \(state)\n".utf8))
    }
    print("backend: \(source.cliName) (\(source.title))")
    await capture.start()
    switch capture.state {
    case .capturing, .noSignal:
        break
    case .permissionDenied:
        let pane = source == .systemTap ? SystemAudioCapture.privacySettingsURL : SystemAudioCapture.screenCapturePrivacySettingsURL
        fail("audio capture is \(capture.state). Allow your terminal in System Settings > Privacy & Security (\(pane.absoluteString)), then re-run.")
    default:
        fail("audio capture is \(capture.state).")
    }
    print("state: \(capture.state)")
    func meter(_ v: Float) -> String { String(repeating: "█", count: Int(v * 12)).padding(toLength: 12, withPad: "·", startingAt: 0) }
    let end = Date().addingTimeInterval(seconds)
    while Date() < end {
        let f = capture.tracker.features()
        let bpm = f.bpm.map { String(format: "%5.1f", $0) } ?? "  ···"
        let tag = capture.state == .noSignal ? "  [no signal: nothing playing, or System Audio Recording not allowed]" : ""
        print(String(format: "\r\u{1B}[2Kbass %@  mid %@  treble %@  beat %@  bpm %@  energy %.2f%@", meter(f.bass), meter(f.mid), meter(f.treble), f.beat > 0.5 ? "●" : "○", bpm, f.energy, tag), terminator: "")
        fflush(stdout)
        try? await Task.sleep(for: .milliseconds(50))
    }
    await capture.stop()
    let final = capture.tracker.features()
    let beats = capture.tracker.beatCount
    let implied = final.bpm.map { String(format: "%.0f", $0 * seconds / 60) } ?? "?"
    print("\n\nbeats detected: \(beats) in \(Int(seconds))s (a steady \(final.bpm.map { String(format: "%.0f", $0) } ?? "?") BPM would give about \(implied)), tempo estimate: \(final.bpm.map { String(format: "%.1f BPM", $0) } ?? "none yet")")

case "palette":
    // Wait a few seconds for the monitor's first reading with a track in it.
    let monitor = NowPlayingMonitor()
    var playing: Track?
    var polls = 0
    for await snapshot in monitor.start() {
        polls += 1
        if let track = snapshot.track { playing = track; break }
        if polls >= 8 { break }
    }
    monitor.stop()
    guard let track = playing else { fail("nothing playing in Spotify or Apple Music") }
    print("♪ \(track.title) — \(track.artist)  (\(track.album))")

    func hex(_ c: RGBA) -> String {
        String(format: "#%02X%02X%02X", Int((c.r * 255).rounded()), Int((c.g * 255).rounded()), Int((c.b * 255).rounded()))
    }
    func block(_ c: RGBA) -> String {
        "\u{1B}[48;2;\(Int((c.r * 255).rounded()));\(Int((c.g * 255).rounded()));\(Int((c.b * 255).rounded()))m      \u{1B}[0m"
    }
    func line(_ label: String, _ c: RGBA) { print("  \(label.padding(toLength: 16, withPad: " ", startingAt: 0)) \(block(c)) \(hex(c))") }

    let provider = ChainedArtworkProvider([PlayerArtworkProvider(), ITunesArtworkProvider()])
    guard let image = await provider.artwork(for: track) else { fail("no artwork available for this track") }
    print("artwork: \(image.width)x\(image.height)")
    guard let palette = PaletteExtractor.extract(from: image) else { fail("could not read colors from the artwork") }
    line("dominant", palette.dominant)
    line("accent", palette.accent)
    line("secondary", palette.secondary)
    line("light primary", palette.lightPrimary)
    line("light secondary", palette.lightSecondary)
    print("  swatches        \(palette.swatches.map(hex).joined(separator: " "))")
    print("  artwork is \(palette.isDark ? "dark" : "light") overall")

case "mood":
    var audioSeconds: Double?
    if let i = args.firstIndex(of: "--audio") {
        guard i + 1 < args.count, let s = Double(args[i + 1]), s > 0 else { usage() }
        audioSeconds = s
    }
    let monitor = NowPlayingMonitor()
    var playing: Track?
    var polls = 0
    for await snapshot in monitor.start() {
        polls += 1
        if let track = snapshot.track { playing = track; break }
        if polls >= 8 { break }
    }
    monitor.stop()
    guard let track = playing else { fail("nothing playing in Spotify or Apple Music") }
    print("♪ \(track.title) — \(track.artist)  (\(track.album))")
    print("genre: \(track.genre.isEmpty ? "n/a (this player does not provide one)" : track.genre)")
    if let g = GenreClassifier.classify(track.genre) {
        print("  genre says: \(g.mood.title) (confidence \(String(format: "%.2f", g.confidence)), matched: \(g.matched.joined(separator: ", ")))")
    } else if !track.genre.isEmpty {
        print("  genre says: nothing (not a genre Lyra knows)")
    }

    var palette: Palette?
    let artProvider = ChainedArtworkProvider([PlayerArtworkProvider(), ITunesArtworkProvider()])
    if let image = await artProvider.artwork(for: track) { palette = PaletteExtractor.extract(from: image) }
    if let p = palette {
        func hexOf(_ c: RGBA) -> String { String(format: "#%02X%02X%02X", Int((c.r * 255).rounded()), Int((c.g * 255).rounded()), Int((c.b * 255).rounded())) }
        print("cover: dominant \(hexOf(p.dominant)), accent \(hexOf(p.accent)), secondary \(hexOf(p.secondary)), \(p.isDark ? "dark" : "light") overall")
    } else {
        print("cover: unavailable")
    }

    var settings = AutoThemeSettings()
    settings.enabled = true
    let themeIDs = BuiltInThemes.all.map(\.id)
    func report(_ title: String, _ decision: ThemeDecision?, _ guess: MoodGuess) {
        print("\n\(title)")
        print("  mood: \(guess.mood.title) (confidence \(String(format: "%.2f", guess.confidence)))")
        for r in guess.reasons { print("  - \(r)") }
        if let d = decision, let theme = BuiltInThemes.theme(id: d.themeID) {
            print("  theme: \(theme.name) (\(d.themeID))  [looked at: \(d.reason)]")
        } else {
            print("  theme: no change (not enough evidence)")
        }
    }
    let engine = AutoThemeEngine(settings: settings, themeIDs: themeIDs, profile: AudioProfile(minSeconds: min(12, audioSeconds ?? 12)))
    let start = ProcessInfo.processInfo.systemUptime
    let early = engine.trackChanged(track: track, palette: palette, now: start)
    report("From genre and cover", early, MoodEngine().guess(genre: track.genre, palette: palette))

    if let seconds = audioSeconds {
        let capture = SystemAudioCapture()
        await capture.start()
        guard capture.state == .capturing else {
            fail("audio capture is \(capture.state). If this is a permission problem, allow Screen & System Audio Recording for your terminal in System Settings > Privacy & Security, then re-run.")
        }
        var profile = AudioProfile(minSeconds: min(12, seconds))
        var refined: ThemeDecision?
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            let now = ProcessInfo.processInfo.systemUptime
            let f = capture.tracker.features()
            profile.add(f, now: now)
            if let d = engine.audio(features: f, now: now) { refined = d }
            try? await Task.sleep(for: .milliseconds(50))
        }
        await capture.stop()
        if let a = profile.summary {
            print(String(format: "\naudio: %.0f s heard, energy %.2f, bass share %.2f, brightness %.2f, dynamics %.2f, tempo %@",
                         a.seconds, a.energy, a.bassShare, a.brightness, a.dynamics, a.tempo.map { String(format: "%.0f BPM", $0) } ?? "unstable"))
        } else {
            print("\naudio: only \(Int(profile.heardSeconds)) s of sound heard, not enough for a profile")
        }
        report("Refined with audio", refined, MoodEngine().guess(genre: track.genre, audio: profile.summary, palette: palette))
    }

default:
    usage()
}
