import Foundation
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

public enum BackgroundError: LocalizedError, Equatable {
    case unsupportedType(String)
    case unreadable(String)
    case tooLarge(String, limit: String)
    case notDecodable(String)
    case saveFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedType(let name):
            return "\"\(name)\" isn't a supported file. Use an image (png, jpg, heic, tiff, gif) or a video (mov, mp4, m4v)."
        case .unreadable(let name): return "Can't read \"\(name)\"."
        case .tooLarge(let name, let limit): return "\"\(name)\" is too large. The limit is \(limit)."
        case .notDecodable(let name): return "\"\(name)\" couldn't be opened as an image or video."
        case .saveFailed(let name): return "Couldn't save \"\(name)\" into the library."
        }
    }
}

/// The player window's backgrounds: generated gradients that ship with the app, plus images and
/// videos the user adds. Files are copied into the library folder, so the originals can move.
///
/// Layout: `Files/` (copies), `Thumbnails/` (320 px PNGs) and `index.json`.
public struct BackgroundLibrary: Sendable {
    public static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "tif", "gif"]
    public static let videoExtensions: Set<String> = ["mov", "mp4", "m4v"]
    static let maxImageBytes: Int64 = 100_000_000
    static let maxVideoBytes: Int64 = 2_000_000_000
    static let thumbnailSize = 320

    public let directory: URL

    public init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lyra/Backgrounds", isDirectory: true)
    }

    private var filesDirectory: URL { directory.appendingPathComponent("Files", isDirectory: true) }
    private var thumbnailsDirectory: URL { directory.appendingPathComponent("Thumbnails", isDirectory: true) }
    private var indexURL: URL { directory.appendingPathComponent("index.json") }

    // MARK: - Built-ins

    /// Generated gradients, so there is a good-looking background before anything is uploaded.
    public static let builtIns: [BackgroundItem] = {
        func gradient(_ id: String, _ name: String, _ stops: [RGBA]) -> BackgroundItem {
            BackgroundItem(id: "builtin.\(id)", name: name, kind: .gradient, stops: stops,
                           palette: BackgroundItem.gradientPalette(stops))
        }
        return [
            gradient("midnight", "Midnight", [RGBA(0.04, 0.05, 0.14), RGBA(0.10, 0.10, 0.30), RGBA(0.35, 0.15, 0.55)]),
            gradient("aurora", "Aurora", [RGBA(0.02, 0.10, 0.15), RGBA(0.05, 0.55, 0.50), RGBA(0.45, 0.25, 0.75)]),
            gradient("sunset", "Sunset", [RGBA(0.15, 0.04, 0.20), RGBA(0.85, 0.25, 0.35), RGBA(1.0, 0.65, 0.25)]),
            gradient("ocean", "Ocean", [RGBA(0.0, 0.08, 0.22), RGBA(0.0, 0.40, 0.65), RGBA(0.20, 0.80, 0.85)]),
            gradient("ember", "Ember", [RGBA(0.10, 0.02, 0.02), RGBA(0.60, 0.10, 0.05), RGBA(1.0, 0.50, 0.10)]),
            gradient("forest", "Forest", [RGBA(0.02, 0.10, 0.06), RGBA(0.08, 0.38, 0.22), RGBA(0.55, 0.75, 0.35)]),
            gradient("graphite", "Graphite", [RGBA(0.05, 0.05, 0.06), RGBA(0.18, 0.18, 0.21), RGBA(0.42, 0.42, 0.48)]),
        ]
    }()

    // MARK: - Reading

    /// Built-ins first, then the user's items in the order they were added.
    public func all() -> [BackgroundItem] { Self.builtIns + userItems() }

    /// The item with `id`, or the first built-in when it no longer exists (a deleted file, say).
    public func item(id: String) -> BackgroundItem {
        all().first { $0.id == id } ?? Self.builtIns[0]
    }

    public func userItems() -> [BackgroundItem] { readIndex() }

    /// The copied file for an image or video item, if it is still there.
    public func fileURL(for item: BackgroundItem) -> URL? {
        guard let name = item.fileName else { return nil }
        let url = filesDirectory.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    public func thumbnailURL(for item: BackgroundItem) -> URL? {
        guard !item.isBuiltIn else { return nil }
        let url = thumbnailsDirectory.appendingPathComponent("\(item.id).png")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Importing

    /// Copies an image or video into the library and returns the new item. Blocks while the
    /// file is inspected (video frames are decoded), so call it off the main thread.
    @discardableResult
    public func importFile(from url: URL) throws -> BackgroundItem {
        let name = url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        let isImage = Self.imageExtensions.contains(ext)
        let isVideo = Self.videoExtensions.contains(ext)
        guard isImage || isVideo else { throw BackgroundError.unsupportedType(name) }
        guard FileManager.default.isReadableFile(atPath: url.path),
              let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int64 else {
            throw BackgroundError.unreadable(name)
        }
        if isImage, size > Self.maxImageBytes { throw BackgroundError.tooLarge(name, limit: "100 MB for images") }
        if isVideo, size > Self.maxVideoBytes { throw BackgroundError.tooLarge(name, limit: "2 GB for videos") }

        // Inspect before copying, so a broken file never lands in the library.
        let thumbnail: CGImage
        if isImage {
            guard let image = Self.imageThumbnail(of: url, maxPixels: Self.thumbnailSize) else { throw BackgroundError.notDecodable(name) }
            thumbnail = image
        } else {
            guard let image = try Self.blocking({ await Self.videoFrame(of: url, maxPixels: Self.thumbnailSize) }) else {
                throw BackgroundError.notDecodable(name)
            }
            thumbnail = image
        }

        let id = "user." + UUID().uuidString.lowercased()
        do {
            try FileManager.default.createDirectory(at: filesDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true)
            let destination = uniqueDestination(for: name)
            try FileManager.default.copyItem(at: url, to: destination)
            guard Self.writePNG(thumbnail, to: thumbnailsDirectory.appendingPathComponent("\(id).png")) else {
                try? FileManager.default.removeItem(at: destination)
                throw BackgroundError.saveFailed(name)
            }

            let item = BackgroundItem(
                id: id, name: (name as NSString).deletingPathExtension, kind: isImage ? .image : .video,
                fileName: destination.lastPathComponent, addedAt: Date(), palette: PaletteExtractor.extract(from: thumbnail))
            try writeIndex(readIndex() + [item])
            return item
        } catch let error as BackgroundError {
            throw error
        } catch {
            throw BackgroundError.saveFailed(name)
        }
    }

    /// Removes a user item and its files. Built-ins can't be deleted. Returns whether anything was removed.
    @discardableResult
    public func delete(id: String) -> Bool {
        guard !id.hasPrefix("builtin."), let item = readIndex().first(where: { $0.id == id }) else { return false }
        if let name = item.fileName { try? FileManager.default.removeItem(at: filesDirectory.appendingPathComponent(name)) }
        try? FileManager.default.removeItem(at: thumbnailsDirectory.appendingPathComponent("\(id).png"))
        try? writeIndex(readIndex().filter { $0.id != id })
        return true
    }

    // MARK: - Index

    private struct IndexFile: Codable {
        var version = 1
        var items: [BackgroundItem]
    }

    /// An unreadable or corrupt index is an empty library, never a crash.
    private func readIndex() -> [BackgroundItem] {
        guard let data = try? Data(contentsOf: indexURL),
              let file = try? JSONDecoder().decode(IndexFile.self, from: data) else { return [] }
        return file.items
    }

    private func writeIndex(_ items: [BackgroundItem]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(IndexFile(items: items)).write(to: indexURL, options: .atomic)
    }

    /// "name.ext", then "name-1.ext", "name-2.ext"... so an import never overwrites another.
    private func uniqueDestination(for fileName: String) -> URL {
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var candidate = filesDirectory.appendingPathComponent(fileName)
        var n = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = filesDirectory.appendingPathComponent("\(base)-\(n).\(ext)")
            n += 1
        }
        return candidate
    }

    // MARK: - Decoding helpers

    static func imageThumbnail(of url: URL, maxPixels: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0 else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// A frame from the middle of the video, at most `maxPixels` on its long side. nil when the
    /// file isn't playable video.
    static func videoFrame(of url: URL, maxPixels: Int) async -> CGImage? {
        let asset = AVURLAsset(url: url)
        guard let playable = try? await asset.load(.isPlayable), playable,
              let tracks = try? await asset.loadTracks(withMediaType: .video), !tracks.isEmpty,
              let duration = try? await asset.load(.duration) else { return nil }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixels, height: maxPixels)
        let seconds = duration.seconds.isFinite ? duration.seconds : 0
        let time = CMTime(seconds: seconds / 2, preferredTimescale: 600)
        return try? await generator.image(at: time).image
    }

    static func writePNG(_ image: CGImage, to url: URL) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }

    /// Runs async work to completion from a synchronous caller. Never call it from the work's own actor.
    private final class ResultBox<T>: @unchecked Sendable { var value: T? }

    static func blocking<T>(_ work: @escaping @Sendable () async -> T) throws -> T {
        let box = ResultBox<T>()
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            box.value = await work()
            done.signal()
        }
        done.wait()
        return box.value!
    }
}
