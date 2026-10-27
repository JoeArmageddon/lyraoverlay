import Foundation

/// The kind of feeling a song has, coarse enough that each mood can own a handful of themes.
/// Raw values are stable: saved settings refer to them.
public enum Mood: String, CaseIterable, Codable, Sendable {
    case energetic, aggressive, party, romantic, chill, dreamy
    case melancholic, dark, epic, retro, acoustic, playful
    /// Nothing is known (or nothing stands out). Never drives a theme change on its own.
    case neutral

    public var title: String {
        switch self {
        case .energetic: return "Energetic"
        case .aggressive: return "Aggressive"
        case .party: return "Party"
        case .romantic: return "Romantic"
        case .chill: return "Chill"
        case .dreamy: return "Dreamy"
        case .melancholic: return "Melancholic"
        case .dark: return "Dark"
        case .epic: return "Epic"
        case .retro: return "Retro"
        case .acoustic: return "Acoustic"
        case .playful: return "Playful"
        case .neutral: return "Balanced"
        }
    }

    public var summary: String {
        switch self {
        case .energetic: return "Fast, loud and bright: rock, pop-punk, drum and bass."
        case .aggressive: return "Heavy and hard-hitting: metal, hardcore, drill."
        case .party: return "Made for dancing: dance, house, reggaeton, disco."
        case .romantic: return "Warm and tender: soul, ballads, love songs."
        case .chill: return "Relaxed and steady: lo-fi, reggae, smooth jazz."
        case .dreamy: return "Hazy and floating: shoegaze, ambient, dream pop."
        case .melancholic: return "Slow and sad: blues, emo, fado."
        case .dark: return "Brooding and shadowy: goth, darkwave, doom."
        case .epic: return "Big and cinematic: orchestral, soundtracks, opera."
        case .retro: return "Throwback sounds: synthwave, oldies, new wave."
        case .acoustic: return "Natural and intimate: folk, country, singer-songwriter."
        case .playful: return "Bright and cheerful: pop, ska, kids and novelty."
        case .neutral: return "No clear signal: the look is left alone."
        }
    }

    /// Moods a user can map to a theme (everything except the neutral fallback).
    public static var selectable: [Mood] { allCases.filter { $0 != .neutral } }
}

/// What the mood engine believes, how sure it is, and why.
public struct MoodGuess: Equatable, Sendable {
    public var mood: Mood
    /// 0...1. Below about 0.3 the evidence is too thin to restyle the app.
    public var confidence: Double
    /// Human-readable evidence, strongest source first.
    public var reasons: [String]
    /// Normalized evidence per mood (0...1, comparable between moods of one guess).
    public var scores: [Mood: Double]

    public init(mood: Mood, confidence: Double, reasons: [String], scores: [Mood: Double] = [:]) {
        self.mood = mood
        self.confidence = confidence
        self.reasons = reasons
        self.scores = scores
    }

    public static let neutral = MoodGuess(mood: .neutral, confidence: 0, reasons: ["nothing to go on"])
}
