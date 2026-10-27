import Foundation

/// Which themes suit which mood, and how one is chosen for a track.
public enum MoodThemes {
    /// Built-in theme ids per mood (at least three each; a unit test checks every id exists in
    /// `BuiltInThemes.all`). Order does not matter: the pick is hashed from the track.
    public static let defaults: [Mood: [String]] = [
        // Fast, bright, forward-leaning: neon tubes, razor type, condensed headlines.
        .energetic: ["builtin.pulse", "builtin.neon", "builtin.razor", "builtin.skyline", "builtin.compact", "builtin.poster"],
        // The metal-looking ones: forge and foundry fire, thorn, katana, punk brush, stencil.
        .aggressive: ["builtin.forge", "builtin.foundry", "builtin.punk", "builtin.katana", "builtin.thorn", "builtin.depot"],
        // Marquee lights, graffiti tags, candy and circus.
        .party: ["builtin.neon", "builtin.street", "builtin.candy", "builtin.big-top", "builtin.marquee", "builtin.arcade"],
        // Handwriting and soft serifs in warm light.
        .romantic: ["builtin.diary", "builtin.elegant", "builtin.sunset", "builtin.library", "builtin.dream-pop"],
        // Quiet, spacious, calm colors.
        .chill: ["builtin.minimal", "builtin.ocean", "builtin.aurora", "builtin.forest", "builtin.friendly"],
        // Glow and haze.
        .dreamy: ["builtin.dream-pop", "builtin.aurora", "builtin.sunset", "builtin.night-drive"],
        // Muted serifs, low light, jazz-club blues.
        .melancholic: ["builtin.noir", "builtin.midnight-jazz", "builtin.editorial", "builtin.library", "builtin.thorn"],
        // Gothic, terminal green, black and white.
        .dark: ["builtin.cathedral", "builtin.thorn", "builtin.noir", "builtin.terminal", "builtin.console"],
        // Film titles and grand serifs.
        .epic: ["builtin.cinema", "builtin.cathedral", "builtin.marquee", "builtin.elegant", "builtin.skyline", "builtin.poster"],
        // Synthwave, pixels, vinyl and arcades.
        .retro: ["builtin.retro-wave", "builtin.night-drive", "builtin.neon", "builtin.arcade", "builtin.cabinet", "builtin.vinyl"],
        // Typewriter, paper, frontier and desert.
        .acoustic: ["builtin.newsprint", "builtin.frontier", "builtin.desert", "builtin.vinyl", "builtin.diary", "builtin.ledger"],
        // Round, bright and bouncy.
        .playful: ["builtin.candy", "builtin.friendly", "builtin.big-top", "builtin.arcade", "builtin.street"],
        // No signal: calm, plain looks.
        .neutral: ["builtin.classic", "builtin.studio", "builtin.editorial", "builtin.minimal"],
    ]

    /// FNV-1a: stable across launches, unlike `hashValue`.
    static func stableHash(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return h
    }

    /// The theme for a mood on a given track, or nil if nothing is allowed.
    ///
    /// Order of precedence:
    ///  1. the user's own pick for this mood (`moodThemeIDs`), if that theme exists. It wins over the
    ///     favorites list, because it is the more specific choice, and is never varied;
    ///  2. otherwise the default list for the mood, limited to favorites (`onlyThemeIDs`, ignoring ids
    ///     that don't exist) when there are any; if no default is a favorite, any favorite may be used;
    ///  3. one entry picked by hashing the track key, so a song always gets the same look; if that
    ///     happens to be the active theme, the next entry is taken so consecutive songs differ.
    public static func pick(mood: Mood, trackKey: String, activeThemeID: String?, settings: AutoThemeSettings,
                            knownThemeIDs: [String]) -> String? {
        let known = Set(knownThemeIDs)
        if let chosen = settings.moodThemeIDs[mood.rawValue], known.contains(chosen) { return chosen }

        let favorites = settings.onlyThemeIDs.filter(known.contains)
        var pool = (defaults[mood] ?? []).filter(known.contains)
        if !favorites.isEmpty {
            let allowed = Set(favorites)
            let restricted = pool.filter(allowed.contains)
            pool = restricted.isEmpty ? Array(Set(favorites)) : restricted
        }
        guard !pool.isEmpty else { return nil }
        pool.sort()   // independent of the table's order
        let index = Int(stableHash(trackKey + "|" + mood.rawValue) % UInt64(pool.count))
        var id = pool[index]
        if id == activeThemeID, pool.count > 1 { id = pool[(index + 1) % pool.count] }
        return id
    }
}
