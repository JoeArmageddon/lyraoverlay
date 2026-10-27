import AppKit

/// Font groups, in the order the picker lists them. Lyra's own fonts come first and the
/// gimmicky system fonts last.
public enum FontCategory: String, CaseIterable, Sendable {
    case originals, handDrawn, sans, serif, display, mono, rounded, condensed, novelty

    public var title: String {
        switch self {
        case .originals: return "Lyra Originals"
        case .handDrawn: return "Lyra Hand-Drawn"
        case .sans: return "Sans Serif"
        case .serif: return "Serif"
        case .display: return "Display"
        case .mono: return "Monospace"
        case .rounded: return "Rounded"
        case .condensed: return "Condensed"
        case .novelty: return "More System Fonts"
        }
    }
}

/// A hand-picked font, ready to choose without importing anything.
public struct FeaturedFont: Identifiable, Equatable, Sendable {
    /// The value stored in `FontSpec.family`: a PostScript name, or "System" for the system font.
    public let id: String
    public let name: String
    public let category: FontCategory

    init(_ id: String, _ name: String, _ category: FontCategory) {
        self.id = id
        self.name = name
        self.category = category
    }
}

extension FontCatalog {
    /// Lyra's own display fonts (see `Fonts/` and `Tools/FontFactory`). They are registered by
    /// `registerBundledFonts()` and shown only once that has found them.
    public static let originals: [FeaturedFont] = [
        FeaturedFont("LyraForge-Regular", "Lyra Forge", .originals),
        FeaturedFont("LyraBlade-Regular", "Lyra Blade", .originals),
        FeaturedFont("LyraStencilOps-Regular", "Lyra Stencil Ops", .originals),
        FeaturedFont("LyraCircuit-Regular", "Lyra Circuit", .originals),
        FeaturedFont("LyraNeonTube-Regular", "Lyra Neon Tube", .originals),
        FeaturedFont("LyraThorn-Regular", "Lyra Thorn", .originals),
        FeaturedFont("LyraMonolineRound-Regular", "Lyra Monoline Round", .originals),
        FeaturedFont("LyraPixel-Regular", "Lyra Pixel", .originals),
    ]

    /// The ids of the eight generated Lyra Originals. Explicit on purpose: every other `Lyra*.ttf`
    /// found in `Fonts/` is a hand-drawn font.
    public static let originalIDs: [String] = originals.map(\.id)

    // MARK: - Cached lists

    private static let featuredCacheLock = NSLock()
    private static var cachedHandDrawn: [FeaturedFont]?
    private static var cachedFeatured: [FeaturedFont]?

    /// Forgets the cached lists so the next read scans the font folders again. Called whenever new
    /// bundled font files are registered or the folders under test change.
    static func invalidateFeaturedCache() {
        featuredCacheLock.withLock {
            cachedHandDrawn = nil
            cachedFeatured = nil
        }
    }

    /// The hand-drawn Lyra fonts: every `Lyra*.ttf` in the bundled Fonts folders that is not one of the
    /// eight generated originals, with its PostScript name as the id and its family name as the display
    /// name, sorted by name. Dropping a new font into `Fonts/` is enough; no code changes. Cached, and
    /// refreshed when `registerBundledFonts()` registers new files. Cheap to read every frame.
    public static var handDrawn: [FeaturedFont] {
        featuredCacheLock.lock()
        defer { featuredCacheLock.unlock() }
        return handDrawnLocked()
    }

    private static func handDrawnLocked() -> [FeaturedFont] {
        if let cached = cachedHandDrawn { return cached }
        let found = scanHandDrawn()
        cachedHandDrawn = found
        return found
    }

    private static func scanHandDrawn() -> [FeaturedFont] {
        let known = Set(originalIDs)
        var seen = Set<String>()
        var fonts: [FeaturedFont] = []
        for dir in bundledFontDirectories() {
            let files = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.lastPathComponent.hasPrefix("Lyra") && supportedExtensions.contains($0.pathExtension.lowercased()) }
                .filter { !$0.lastPathComponent.contains(".tmp") }
            for file in files {
                guard let face = faces(in: file).first, !known.contains(face.postScript), seen.insert(face.postScript).inserted else { continue }
                fonts.append(FeaturedFont(face.postScript, face.family, .handDrawn))
            }
        }
        return fonts.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Every font the picker offers by name. Ids are exact PostScript names so each resolves to its
    /// own face instead of the family default. The system fonts here are the tasteful, useful
    /// ones; the gimmicky ones are under `.novelty` and no theme uses them. Cached like `handDrawn`.
    public static var featured: [FeaturedFont] {
        featuredCacheLock.lock()
        defer { featuredCacheLock.unlock() }
        if let cached = cachedFeatured { return cached }
        let all = originals + handDrawnLocked() + systemFonts
        cachedFeatured = all
        return all
    }

    private static let systemFonts: [FeaturedFont] = [
        // Sans serif
        FeaturedFont("System", "SF Pro (System)", .sans),
        FeaturedFont("AvenirNext-Heavy", "Avenir Next Heavy", .sans),
        FeaturedFont("AvenirNext-UltraLight", "Avenir Next Ultra Light", .sans),
        FeaturedFont("HelveticaNeue-Light", "Helvetica Neue Light", .sans),
        FeaturedFont("Futura-Bold", "Futura Bold", .sans),
        FeaturedFont("GillSans-Bold", "Gill Sans Bold", .sans),
        FeaturedFont("Verdana-Bold", "Verdana Bold", .sans),
        FeaturedFont("TrebuchetMS-Bold", "Trebuchet Bold", .sans),
        FeaturedFont("Optima-ExtraBlack", "Optima Extra Black", .sans),
        // Serif and slab
        FeaturedFont("Didot-Bold", "Didot Bold", .serif),
        FeaturedFont("BodoniSvtyTwoITCTT-Bold", "Bodoni 72 Bold", .serif),
        FeaturedFont("Baskerville-Bold", "Baskerville Bold", .serif),
        FeaturedFont("Georgia-Bold", "Georgia Bold", .serif),
        FeaturedFont("HoeflerText-Black", "Hoefler Text Black", .serif),
        FeaturedFont("Palatino-Bold", "Palatino Bold", .serif),
        FeaturedFont("Cochin-Bold", "Cochin Bold", .serif),
        FeaturedFont("BigCaslon-Medium", "Big Caslon", .serif),
        FeaturedFont("Charter-Black", "Charter Black", .serif),
        FeaturedFont("Superclarendon-Black", "Superclarendon Black", .serif),
        FeaturedFont("Rockwell-Bold", "Rockwell Bold", .serif),
        FeaturedFont("AmericanTypewriter-Bold", "American Typewriter Bold", .serif),
        // Display
        FeaturedFont("Impact", "Impact", .display),
        FeaturedFont("Copperplate-Bold", "Copperplate Bold", .display),
        // Monospace
        FeaturedFont("Menlo-Bold", "Menlo Bold", .mono),
        FeaturedFont("CourierNewPS-BoldMT", "Courier New Bold", .mono),
        FeaturedFont("Monaco", "Monaco", .mono),
        FeaturedFont("AndaleMono", "Andale Mono", .mono),
        // Rounded
        FeaturedFont("ArialRoundedMTBold", "Arial Rounded Bold", .rounded),
        // Condensed
        FeaturedFont("AvenirNextCondensed-Bold", "Avenir Next Condensed", .condensed),
        FeaturedFont("DINCondensed-Bold", "DIN Condensed", .condensed),
        FeaturedFont("DINAlternate-Bold", "DIN Alternate", .condensed),
        FeaturedFont("HelveticaNeue-CondensedBlack", "Helvetica Neue Condensed Black", .condensed),
        FeaturedFont("Futura-CondensedExtraBold", "Futura Condensed", .condensed),
        // More system fonts: script, handwriting and novelty faces. Available, never the default.
        FeaturedFont("SnellRoundhand-Black", "Snell Roundhand Black", .novelty),
        FeaturedFont("Apple-Chancery", "Apple Chancery", .novelty),
        FeaturedFont("BrushScriptMT", "Brush Script", .novelty),
        FeaturedFont("BradleyHandITCTT-Bold", "Bradley Hand", .novelty),
        FeaturedFont("Noteworthy-Bold", "Noteworthy Bold", .novelty),
        FeaturedFont("SignPainter-HouseScript", "SignPainter", .novelty),
        FeaturedFont("Zapfino", "Zapfino", .novelty),
        FeaturedFont("Chalkduster", "Chalkduster", .novelty),
        FeaturedFont("MarkerFelt-Wide", "Marker Felt Wide", .novelty),
        FeaturedFont("ChalkboardSE-Bold", "Chalkboard SE Bold", .novelty),
        FeaturedFont("ComicSansMS-Bold", "Comic Sans Bold", .novelty),
        FeaturedFont("Papyrus", "Papyrus", .novelty),
        FeaturedFont("Herculanum", "Herculanum", .novelty),
        FeaturedFont("Phosphate-Solid", "Phosphate", .novelty),
        FeaturedFont("Luminari-Regular", "Luminari", .novelty),
        FeaturedFont("PartyLetPlain", "Party LET", .novelty),
        FeaturedFont("Trattatello", "Trattatello", .novelty),
        FeaturedFont("Silom", "Silom", .novelty),
    ]

    /// The featured fonts this Mac actually has, so a picker never offers one that would silently
    /// fall back to the system font. Looking registers Lyra's own fonts first.
    public static func availableFeatured() -> [FeaturedFont] {
        registerBundledFonts()
        return featured.filter { isInstalled($0.id) }
    }

    /// Available featured fonts grouped by category, in a stable order, skipping empty categories.
    public static func featuredByCategory() -> [(FontCategory, [FeaturedFont])] {
        let available = availableFeatured()
        return FontCategory.allCases.compactMap { category in
            let fonts = available.filter { $0.category == category }
            return fonts.isEmpty ? nil : (category, fonts)
        }
    }
}
