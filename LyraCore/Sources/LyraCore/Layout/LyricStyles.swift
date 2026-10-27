import Foundation

public struct LyricStyleInfo: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let summary: String

    public init(id: String, name: String, summary: String) {
        self.id = id
        self.name = name
        self.summary = summary
    }
}

/// The available lyric styles. Settings and themes refer to a style by `id`.
public enum LyricStyles {
    public static let defaultID = "karaoke"

    public static let all: [LyricStyleInfo] = [
        LyricStyleInfo(id: "karaoke", name: "Karaoke Line",
                       summary: "The current line, centered, with each word filling in as it is sung and a preview of the next."),
        LyricStyleInfo(id: "scroll", name: "Scrolling List",
                       summary: "A few lines at once that glide upward, with the current line large and the rest fading away."),
        LyricStyleInfo(id: "typewriter", name: "Typewriter",
                       summary: "Words appear only as they are sung, while the previous line fades out above."),
        LyricStyleInfo(id: "pop", name: "Pop",
                       summary: "Like Karaoke Line, but every word bounces as it starts."),
        LyricStyleInfo(id: "wave", name: "Wave",
                       summary: "Words ride a gentle wave, and the word being sung lifts above the rest."),
        LyricStyleInfo(id: "focus", name: "Word Focus",
                       summary: "The current word fills the screen, with the full line small underneath."),
        LyricStyleInfo(id: "cinematic", name: "Cinematic",
                       summary: "Every line is cut like a film title shot: a hero word at scale, the rest composed around it, a slow camera move and a punchy transition."),
    ]

    /// Unknown ids (a theme from a newer version, a hand-edited file) fall back to the default.
    public static func style(id: String) -> LyricStyle {
        switch id {
        case "scroll": return ScrollingListStyle()
        case "typewriter": return TypewriterStyle()
        case "pop": return PopStyle()
        case "wave": return WaveStyle()
        case "focus": return FocusStyle()
        case "cinematic": return CinematicStyle()
        default: return KaraokeLineStyle()
        }
    }
}
