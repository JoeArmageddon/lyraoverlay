import Foundation

public enum ThemeError: LocalizedError, Equatable {
    case unreadable
    case notATheme
    case tooLarge
    case unsupportedVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .unreadable: return "The file could not be read."
        case .notATheme: return "This file is not a Lyra theme."
        case .tooLarge: return "This file is too large to be a theme."
        case .unsupportedVersion(let v): return "This theme was made by a newer version of Lyra (format \(v))."
        }
    }
}

/// User themes as one JSON file each, plus import and export for sharing.
public struct ThemeStore: Sendable {
    public let directory: URL
    /// A theme is a few KB; anything much larger is not one.
    static let maxFileSize = 1_000_000

    public init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lyra/Themes", isDirectory: true)
    }

    /// Built-ins first, then the user's themes by name.
    public func all() -> [Theme] { BuiltInThemes.all + userThemes() }

    /// Skips files that are not valid themes, so one bad file never hides the rest.
    public func userThemes() -> [Theme] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "json" }
            .compactMap { try? Self.read($0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func theme(id: String) -> Theme? { all().first { $0.id == id } }

    /// Saves a user theme. A theme with a built-in or empty id gets a fresh user id.
    @discardableResult
    public func save(_ theme: Theme) throws -> Theme {
        var theme = theme
        theme.name = theme.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if theme.name.isEmpty { theme.name = "Untitled" }
        if theme.id.isEmpty || theme.id.hasPrefix("builtin.") { theme.id = Self.newID() }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.encode(theme).write(to: fileURL(for: theme), options: .atomic)
        return theme
    }

    public func delete(id: String) {
        guard let url = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))?
            .first(where: { (try? Self.read($0))?.id == id }) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Writes a shareable copy; the format is the same as the stored files.
    public func export(_ theme: Theme, to url: URL) throws {
        try Self.encode(theme).write(to: url, options: .atomic)
    }

    /// Reads a shared file and saves it as a new user theme with a fresh id, so importing
    /// never overwrites anything and the same file can be imported twice.
    @discardableResult
    public func importTheme(from url: URL) throws -> Theme {
        var theme = try Self.read(url)
        theme.id = Self.newID()
        let existing = Set(all().map(\.name))
        if existing.contains(theme.name) {
            var n = 2
            while existing.contains("\(theme.name) \(n)") { n += 1 }
            theme.name = "\(theme.name) \(n)"
        }
        return try save(theme)
    }

    // MARK: - Files

    static func newID() -> String { "user." + UUID().uuidString.lowercased() }

    private func fileURL(for theme: Theme) -> URL {
        let slug = theme.name.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
            .split(separator: "-", omittingEmptySubsequences: true).joined(separator: "-")
        let short = theme.id.replacingOccurrences(of: "user.", with: "").prefix(8)
        return directory.appendingPathComponent("\(slug.isEmpty ? "theme" : slug)-\(short).json")
    }

    static func encode(_ theme: Theme) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(ThemeFile(version: Theme.formatVersion, theme: theme))
    }

    static func read(_ url: URL) throws -> Theme {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let data = try? Data(contentsOf: url) else { throw ThemeError.unreadable }
        if (attributes[.size] as? Int ?? data.count) > maxFileSize { throw ThemeError.tooLarge }

        // Check the version first so a newer format gives a useful message instead of "not a theme".
        struct VersionProbe: Decodable { var version: Int }
        guard let probe = try? JSONDecoder().decode(VersionProbe.self, from: data) else { throw ThemeError.notATheme }
        guard probe.version <= Theme.formatVersion else { throw ThemeError.unsupportedVersion(probe.version) }
        guard let file = try? JSONDecoder().decode(ThemeFile.self, from: data) else { throw ThemeError.notATheme }
        return file.theme
    }
}
