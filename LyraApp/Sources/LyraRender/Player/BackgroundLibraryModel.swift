import AppKit
import LyraCore

/// The background library as the UI sees it: a published list, imports that run off the main
/// thread, and thumbnails. Main thread only.
final class BackgroundLibraryModel: ObservableObject {
    @Published private(set) var items: [BackgroundItem]
    /// A short message for the picker to show under the grid (an import error, for instance).
    @Published var message: String?
    @Published private(set) var isImporting = false

    let library: BackgroundLibrary
    /// Called on the main thread with the last item of a successful import, so it can be selected.
    var onImported: ((BackgroundItem) -> Void)?

    private let thumbnails = NSCache<NSString, NSImage>()
    private let queue = DispatchQueue(label: "lyra.background.import", qos: .userInitiated)

    init(library: BackgroundLibrary) {
        self.library = library
        self.items = library.all()
    }

    func reload() { items = library.all() }

    /// Imports the files one after another. Unsupported ones are reported but never stop the rest.
    func importFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        isImporting = true
        message = nil
        let library = library
        queue.async { [weak self] in
            var last: BackgroundItem?
            var errors: [String] = []
            for url in urls {
                do { last = try library.importFile(from: url) } catch { errors.append(error.localizedDescription) }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.isImporting = false
                self.reload()
                if let first = errors.first {
                    self.message = errors.count == 1 ? first : "\(errors.count) files couldn't be added. \(first)"
                }
                if let last { self.onImported?(last) }
            }
        }
    }

    func delete(_ item: BackgroundItem) {
        guard library.delete(id: item.id) else { return }
        thumbnails.removeObject(forKey: item.id as NSString)
        reload()
    }

    func thumbnail(for item: BackgroundItem) -> NSImage? {
        if let cached = thumbnails.object(forKey: item.id as NSString) { return cached }
        guard let url = library.thumbnailURL(for: item), let image = NSImage(contentsOf: url) else { return nil }
        thumbnails.setObject(image, forKey: item.id as NSString)
        return image
    }

    /// True for files the library could take: an image or video by extension.
    static func isSupported(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return BackgroundLibrary.imageExtensions.contains(ext) || BackgroundLibrary.videoExtensions.contains(ext)
    }
}
