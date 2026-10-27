import AppKit
import CoreText
import UniformTypeIdentifiers

public enum FontImportError: LocalizedError, Equatable {
    case unreadable(String)
    case unsupportedType(String)
    case notAFont(String)
    case registrationFailed(String)
    /// The font is already available: (file name, who has it).
    case duplicate(String, String)
    case outsideUserFolder(String)
    case notInstalled(String)

    public var errorDescription: String? {
        switch self {
        case .unreadable(let name): return "Can't read \"\(name)\"."
        case .unsupportedType(let name): return "\"\(name)\" isn't a font file. Use a .ttf, .otf, .ttc or .otc file."
        case .notAFont(let name): return "\"\(name)\" doesn't contain a usable font."
        case .registrationFailed(let name): return "macOS couldn't load the font in \"\(name)\"."
        case .duplicate(let name, let owner): return "\"\(name)\" is already available: \(owner)."
        case .outsideUserFolder(let name): return "\"\(name)\" isn't in Lyra's custom fonts folder, so Lyra won't delete it."
        case .notInstalled(let name): return "\"\(name)\" isn't one of your custom fonts."
        }
    }
}

/// A font file the user added to Lyra (kept in `FontCatalog.userFontsDirectory`).
public struct UserFont: Identifiable, Equatable, Sendable {
    public var id: String { fileName }
    public let fileName: String
    public let url: URL
    public let families: [String]
    public let postScriptNames: [String]
    public let byteCount: Int
    /// True while the font is loaded for this process (it is at launch and right after an import).
    public let isRegistered: Bool

    /// What the picker shows as the font's name.
    public var displayName: String { families.first ?? (fileName as NSString).deletingPathExtension }
    /// The value stored in `FontSpec.family` when this font is chosen: its first PostScript name.
    public var fontID: String { postScriptNames.first ?? displayName }
}

/// The outcome for one file of a multi-file import.
public struct ImportResult: Equatable, Sendable {
    public let sourceName: String
    public let storedFileName: String?
    public let families: [String]
    public let postScriptNames: [String]
    public let error: FontImportError?

    public var succeeded: Bool { error == nil }
    /// The value to store in `FontSpec.family` for the first imported font.
    public var fontID: String? { postScriptNames.first ?? families.first }

    /// One sentence for a status line: "Added Foo and Bar." or the first error, plus a count of the rest.
    public static func summary(_ results: [ImportResult]) -> String {
        guard !results.isEmpty else { return "No fonts were added." }
        let good = results.filter(\.succeeded)
        let bad = results.filter { !$0.succeeded }
        var parts: [String] = []
        if !good.isEmpty {
            let names = good.flatMap(\.families)
            parts.append("Added \(names.prefix(3).joined(separator: ", "))\(names.count > 3 ? " and \(names.count - 3) more" : "").")
        }
        if let first = bad.first?.error?.errorDescription {
            parts.append(first + (bad.count > 1 ? " (\(bad.count - 1) more couldn't be added.)" : ""))
        }
        return parts.joined(separator: " ")
    }
}

/// The fonts a user can pick: everything installed, plus fonts they import into Lyra's own folder.
public enum FontCatalog {
    static let supportedExtensions: Set<String> = ["ttf", "otf", "ttc", "otc"]

    /// Tests point this at a temp folder so they never touch the real Application Support.
    static var directoryOverride: URL?

    public static var userFontsDirectory: URL {
        directoryOverride ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lyra/Fonts", isDirectory: true)
    }

    /// "System" first, then installed families sorted case-insensitively. Hidden system
    /// families (names starting with ".") are left out.
    public static func families() -> [String] {
        var seen: Set<String> = ["System"]
        var names: [String] = []
        for family in NSFontManager.shared.availableFontFamilies where !family.hasPrefix(".") {
            if seen.insert(family).inserted { names.append(family) }
        }
        names.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return ["System"] + names
    }

    // MARK: - Fonts that ship with Lyra

    /// Tests point this at a folder of fonts instead of the bundle and the project.
    static var bundledDirectoryOverride: URL? { didSet { invalidateFeaturedCache() } }

    private static let registrationLock = NSLock()
    private static var registeredBundledPaths: Set<String> = []

    /// Where Lyra's own fonts may live, most specific first: the packaged app's `Resources/Fonts`,
    /// a folder named by `LYRA_FONTS_DIR`, and, while developing, a `Fonts/` folder found by walking
    /// up from the running program (or the working directory) to the project.
    static func bundledFontDirectories(resourceURL: URL? = Bundle.main.resourceURL,
                                       environment: [String: String] = ProcessInfo.processInfo.environment,
                                       executableURL: URL? = Bundle.main.executableURL,
                                       workingDirectory: String = FileManager.default.currentDirectoryPath) -> [URL] {
        if let override = bundledDirectoryOverride { return [override] }
        var dirs: [URL] = []
        if let bundled = resourceURL?.appendingPathComponent("Fonts", isDirectory: true), containsLyraFonts(bundled) { dirs.append(bundled) }
        if let env = environment["LYRA_FONTS_DIR"] {
            let url = URL(fileURLWithPath: env, isDirectory: true)
            if containsLyraFonts(url) { dirs.append(url) }
        }
        for start in [executableURL?.deletingLastPathComponent(), URL(fileURLWithPath: workingDirectory)].compactMap({ $0 }) {
            var url = start
            for _ in 0..<10 {
                let candidate = url.appendingPathComponent("Fonts", isDirectory: true)
                if containsLyraFonts(candidate) { dirs.append(candidate); break }
                url.deleteLastPathComponent()
            }
        }
        var seen = Set<String>()
        return dirs.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    private static func containsLyraFonts(_ dir: URL) -> Bool {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return files.contains { $0.hasPrefix("Lyra") && $0.hasSuffix("-Regular.ttf") }
    }

    /// Registers Lyra's own fonts (the Lyra Originals) for this process. Safe to call any number of
    /// times and from anywhere: a font file is only registered once. Returns how many files were
    /// newly registered. Never throws.
    @discardableResult
    public static func registerBundledFonts() -> Int {
        registrationLock.lock()
        defer { registrationLock.unlock() }
        var added = 0
        for dir in bundledFontDirectories() {
            let files = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
                .filter { supportedExtensions.contains($0.pathExtension.lowercased()) }
                .filter { !$0.lastPathComponent.contains(".tmp") && !$0.lastPathComponent.hasPrefix(".") }   // half-written files
                .filter { registeredBundledPaths.insert($0.standardizedFileURL.path).inserted }
            guard !files.isEmpty else { continue }
            // Errors are expected for a font the process already has (the same family from another
            // folder); it is usable either way.
            CTFontManagerRegisterFontsForURLs(files as CFArray, .process, nil)
            added += files.count
        }
        if added > 0 { invalidateFeaturedCache() }
        return added
    }

    /// The name to show for a stored `FontSpec.family`: the featured name when there is one.
    public static func displayName(for family: String) -> String {
        featured.first { $0.id == family }?.name ?? (family.isEmpty ? "System" : family)
    }

    /// Matches by family name or PostScript name, the same two lookups `FontResolver` uses.
    public static func isInstalled(_ family: String) -> Bool {
        if family == "System" { return true }
        if isRemoved(family) { return false }
        if family.hasPrefix("Lyra") { registerBundledFonts() }
        if NSFontManager.shared.availableFontFamilies.contains(family) { return true }
        return NSFont(name: family, size: 12) != nil
    }

    // MARK: - Custom fonts

    /// Posted (on the main queue) after fonts are added to or removed from the user folder, so open
    /// pickers can refresh.
    public static let didChangeNotification = Notification.Name("LyraFontCatalogDidChange")

    /// CoreText takes a moment to forget an unregistered font. Names removed here count as gone at once.
    private static let removedLock = NSLock()
    private static var removedNames: Set<String> = []

    static func isRemoved(_ name: String) -> Bool { removedLock.withLock { removedNames.contains(name) } }

    /// A font that macOS or Lyra currently provides under this name (family or PostScript).
    private static func isLoadedByName(_ name: String) -> Bool {
        !isRemoved(name) && NSFont(name: name, size: 12) != nil
    }

    private static func announceChange() {
        DispatchQueue.main.async { NotificationCenter.default.post(name: didChangeNotification, object: nil) }
    }

    private static func fontFiles(in directory: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { supportedExtensions.contains($0.pathExtension.lowercased()) && !$0.lastPathComponent.hasPrefix(".") }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// (family, PostScript name) for every face in a font file; empty when it isn't a font.
    static func faces(in url: URL) -> [(family: String, postScript: String)] {
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] else { return [] }
        return descriptors.compactMap { d in
            guard let family = CTFontDescriptorCopyAttribute(d, kCTFontFamilyNameAttribute) as? String,
                  let ps = CTFontDescriptorCopyAttribute(d, kCTFontNameAttribute) as? String else { return nil }
            return (family, ps)
        }
    }

    private static func isLoaded(_ postScript: String, from url: URL) -> Bool {
        guard NSFont(name: postScript, size: 12) != nil else { return false }
        let descriptor = CTFontDescriptorCreateWithNameAndSize(postScript as CFString, 12)
        guard let loaded = CTFontDescriptorCopyAttribute(descriptor, kCTFontURLAttribute) as? URL else { return false }
        return loaded.resolvingSymlinksInPath().path == url.resolvingSymlinksInPath().path
    }

    /// The imported fonts, sorted by name. A file that can't be read as a font is still listed (with no
    /// names) so the user can remove it.
    public static func userFonts() -> [UserFont] {
        let fonts: [UserFont] = fontFiles(in: userFontsDirectory).map { url in
            let faces = faces(in: url)
            var families: [String] = []
            for f in faces where !families.contains(f.family) { families.append(f.family) }
            let size = ((try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:])[.size] as? Int ?? 0
            return UserFont(fileName: url.lastPathComponent, url: url, families: families, postScriptNames: faces.map(\.postScript),
                            byteCount: size,
                            isRegistered: !faces.isEmpty && faces.allSatisfy { isLoaded($0.postScript, from: url) })
        }
        return fonts.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    /// Why a PostScript name can't be added, or nil when it is new: another imported font, a font that
    /// ships with Lyra, or one macOS already has.
    private static func existingOwner(of postScript: String) -> String? {
        for font in userFonts() where font.postScriptNames.contains(postScript) {
            return "you already added it (\(font.fileName))"
        }
        if featured.contains(where: { $0.id == postScript }) { return "it ships with Lyra" }
        if isLoadedByName(postScript) { return "macOS already has it installed" }
        return nil
    }

    /// Imports one file. Never throws; the result says what happened.
    public static func importOne(_ url: URL) -> ImportResult {
        let name = url.lastPathComponent
        func failure(_ error: FontImportError) -> ImportResult {
            ImportResult(sourceName: name, storedFileName: nil, families: [], postScriptNames: [], error: error)
        }
        guard supportedExtensions.contains(url.pathExtension.lowercased()) else { return failure(.unsupportedType(name)) }
        guard FileManager.default.isReadableFile(atPath: url.path) else { return failure(.unreadable(name)) }
        let faces = faces(in: url)
        guard !faces.isEmpty else { return failure(.notAFont(name)) }

        // Duplicate only when every face is already available; a collection with one new face is fine.
        let owners = faces.map { existingOwner(of: $0.postScript) }
        if owners.allSatisfy({ $0 != nil }), let reason = owners.first ?? nil { return failure(.duplicate(name, reason)) }

        let directory = userFontsDirectory
        let destination = uniqueDestination(for: name, in: directory)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: destination)
        } catch {
            return failure(.unreadable(name))
        }
        var cfError: Unmanaged<CFError>?
        if !CTFontManagerRegisterFontsForURL(destination as CFURL, .process, &cfError) {
            // Already registered under another path: usable either way. Otherwise undo the copy.
            if !faces.allSatisfy({ isLoadedByName($0.postScript) }) {
                try? FileManager.default.removeItem(at: destination)
                return failure(.registrationFailed(name))
            }
        }
        var families: [String] = []
        for f in faces where !families.contains(f.family) { families.append(f.family) }
        removedLock.withLock { removedNames.subtract(faces.map(\.postScript)); removedNames.subtract(families) }
        return ImportResult(sourceName: name, storedFileName: destination.lastPathComponent, families: families,
                            postScriptNames: faces.map(\.postScript), error: nil)
    }

    /// Imports several files at once, each reported separately. Fonts show up in the pickers right away.
    @discardableResult
    public static func importFonts(urls: [URL]) -> [ImportResult] {
        let results = urls.map(importOne)
        if results.contains(where: \.succeeded) { announceChange() }
        return results
    }

    /// Copies one font file into Lyra's fonts folder and loads it for this process.
    /// Returns the family names the file provides.
    @discardableResult
    public static func importFont(from url: URL) throws -> [String] {
        let result = importFonts(urls: [url])[0]
        if let error = result.error { throw error }
        return result.families
    }

    /// Deletes an imported font's file and unloads it for this process. Refuses anything that isn't a
    /// file directly inside the user fonts folder. Settings and themes are left alone: a theme that
    /// still names the font falls back to the system font.
    public static func removeUserFont(at url: URL) throws {
        let folder = userFontsDirectory.resolvingSymlinksInPath().standardizedFileURL
        let file = url.resolvingSymlinksInPath().standardizedFileURL
        guard file.deletingLastPathComponent().path == folder.path, supportedExtensions.contains(file.pathExtension.lowercased()) else {
            throw FontImportError.outsideUserFolder(url.lastPathComponent)
        }
        guard FileManager.default.fileExists(atPath: file.path) else { throw FontImportError.notInstalled(url.lastPathComponent) }
        let gone = faces(in: file)
        removedLock.withLock { removedNames.formUnion(gone.map(\.postScript) + gone.map(\.family)) }
        var cfError: Unmanaged<CFError>?
        _ = CTFontManagerUnregisterFontsForURL(url as CFURL, .process, &cfError)   // fine if it was never loaded
        _ = CTFontManagerUnregisterFontsForURL(file as CFURL, .process, &cfError)
        do { try FileManager.default.removeItem(at: file) } catch { throw FontImportError.unreadable(file.lastPathComponent) }
        announceChange()
    }

    public static func removeUserFont(_ font: UserFont) throws { try removeUserFont(at: font.url) }

    /// Loads the fonts that ship with Lyra and every font already in the user folder.
    /// Call at launch. Never throws.
    public static func registerUserFonts() {
        registerBundledFonts()
        let fonts = fontFiles(in: userFontsDirectory)
        guard !fonts.isEmpty else { return }
        CTFontManagerRegisterFontsForURLs(fonts as CFArray, .process, nil)
    }

    /// Opens the custom fonts folder in Finder, creating it first. For a menu item.
    public static func revealUserFontsFolder() { revealUserFontsFolder(open: { NSWorkspace.shared.open($0) }) }

    /// The same with the opening step injected, so tests don't open Finder windows.
    static func revealUserFontsFolder(open: (URL) -> Void) {
        try? FileManager.default.createDirectory(at: userFontsDirectory, withIntermediateDirectories: true)
        open(userFontsDirectory)
    }

    /// Shows the open panel (several files allowed), imports the choices, and returns one result per
    /// file (empty when the panel is cancelled). For a menu item and the picker's button.
    @MainActor
    @discardableResult
    public static func addCustomFontsFromPanel() -> [ImportResult] {
        let panel = makeFontOpenPanel()
        guard panel.runModal() == .OK else { return [] }
        return importFonts(urls: panel.urls)
    }

    @MainActor
    static func makeFontOpenPanel() -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.title = "Add Custom Font"
        panel.message = "Choose one or more font files (.ttf, .otf, .ttc, .otc)."
        panel.prompt = "Add"
        panel.allowedContentTypes = ["ttf", "otf", "ttc", "otc"].compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        return panel
    }

    /// "Name.ttf", then "Name-1.ttf", "Name-2.ttf"... so an import never overwrites another.
    private static func uniqueDestination(for fileName: String, in directory: URL) -> URL {
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var candidate = directory.appendingPathComponent(fileName)
        var n = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base)-\(n).\(ext)")
            n += 1
        }
        return candidate
    }
}
