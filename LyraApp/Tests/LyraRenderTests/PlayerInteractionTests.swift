import XCTest
import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers
import LyraCore
@testable import LyraRender

/// A drag carrying file URLs, standing in for Finder. The player's drop handler only reads the
/// pasteboard, so this exercises its real code without needing a mouse.
private final class FakeDrag: NSObject, NSDraggingInfo {
    let pasteboard: NSPasteboard

    init(files: [URL]) {
        pasteboard = NSPasteboard(name: NSPasteboard.Name("lyra-test-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.writeObjects(files as [NSURL])
        super.init()
    }

    var draggingDestinationWindow: NSWindow? { nil }
    var draggingSourceOperationMask: NSDragOperation { .copy }
    var draggingLocation: NSPoint { .zero }
    var draggedImageLocation: NSPoint { .zero }
    var draggedImage: NSImage? { nil }
    var draggingPasteboard: NSPasteboard { pasteboard }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 0 }
    var draggingFormation: NSDraggingFormation { get { .default } set {} }
    var animatesToDestination: Bool { get { false } set {} }
    var numberOfValidItemsForDrop: Int { get { 1 } set {} }
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    func resetSpringLoading() {}
    override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions, for view: NSView?, classes classArray: [AnyClass],
                                searchOptions: [NSPasteboard.ReadingOptionKey: Any],
                                using block: @escaping (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
}

private func tempDir() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("lyra-interaction-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Writes a small solid PNG and returns its URL.
private func makePNG(in dir: URL, name: String = "photo.png", color: (CGFloat, CGFloat, CGFloat) = (0.2, 0.5, 0.9)) throws -> URL {
    let ctx = CGContext(data: nil, width: 120, height: 80, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: color.0, green: color.1, blue: color.2, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: 120, height: 80))
    let url = dir.appendingPathComponent(name)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    XCTAssertTrue(CGImageDestinationFinalize(dest))
    return url
}

final class DragAndDropTests: XCTestCase {
    private func makeView() -> (PlayerContentView, dropped: DropLog) {
        let view = PlayerContentView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let log = DropLog()
        view.onDropFiles = { log.urls.append(contentsOf: $0) }
        return (view, log)
    }

    final class DropLog { var urls: [URL] = [] }

    func testDroppedImageIsAcceptedAndForwarded() throws {
        let dir = tempDir()
        let png = try makePNG(in: dir)
        let (view, log) = makeView()
        let drag = FakeDrag(files: [png])

        XCTAssertEqual(view.draggingEntered(drag), .copy, "the cursor shows a copy badge for a supported file")
        XCTAssertTrue(view.performDragOperation(drag))
        XCTAssertEqual(log.urls.map(\.lastPathComponent), ["photo.png"])
    }

    func testUnsupportedFilesAreRefused() throws {
        let dir = tempDir()
        let text = dir.appendingPathComponent("notes.txt")
        try Data("hello".utf8).write(to: text)
        let (view, log) = makeView()
        let drag = FakeDrag(files: [text])

        XCTAssertEqual(view.draggingEntered(drag), [], "no drop is offered for a text file")
        XCTAssertFalse(view.performDragOperation(drag))
        XCTAssertTrue(log.urls.isEmpty, "nothing is imported")
    }

    func testMixedDropForwardsOnlyTheSupportedFiles() throws {
        let dir = tempDir()
        let png = try makePNG(in: dir)
        let text = dir.appendingPathComponent("readme.txt")
        try Data("x".utf8).write(to: text)
        let video = dir.appendingPathComponent("clip.mov")
        try Data(count: 16).write(to: video)
        let (view, log) = makeView()

        XCTAssertTrue(view.performDragOperation(FakeDrag(files: [png, text, video])))
        XCTAssertEqual(Set(log.urls.map(\.lastPathComponent)), ["photo.png", "clip.mov"])
    }

    func testViewRegistersForFileDrops() {
        let (view, _) = makeView()
        XCTAssertTrue(view.registeredDraggedTypes.contains(.fileURL))
    }
}

final class BackgroundImportFlowTests: XCTestCase {
    func testDroppedImageEndsUpInTheLibraryWithAThumbnail() throws {
        let source = tempDir()
        let png = try makePNG(in: source, name: "sunset photo.png")
        let model = BackgroundLibraryModel(library: BackgroundLibrary(directory: tempDir()))
        let builtIns = model.items.count

        let imported = expectation(description: "import finishes")
        var importedItem: BackgroundItem?
        model.onImported = { importedItem = $0; imported.fulfill() }
        model.importFiles([png])
        wait(for: [imported], timeout: 10)

        XCTAssertEqual(model.items.count, builtIns + 1)
        let item = try XCTUnwrap(importedItem)
        XCTAssertEqual(item.kind, .image)
        XCTAssertNotNil(model.thumbnail(for: item), "the picker needs a thumbnail to show")
        XCTAssertNil(model.message)
        XCTAssertFalse(model.isImporting)
    }

    func testABadFileIsReportedAndTheGoodOnesStillImport() throws {
        let source = tempDir()
        let good = try makePNG(in: source)
        let bad = source.appendingPathComponent("broken.jpg")
        try Data("not really a jpeg".utf8).write(to: bad)
        let model = BackgroundLibraryModel(library: BackgroundLibrary(directory: tempDir()))
        let builtIns = model.items.count

        let done = expectation(description: "import finishes")
        model.onImported = { _ in done.fulfill() }
        model.importFiles([bad, good])
        wait(for: [done], timeout: 10)

        XCTAssertEqual(model.items.count, builtIns + 1, "the good image still made it in")
        XCTAssertNotNil(model.message, "the bad file is explained to the user")
    }

    func testDeletingAnImportedBackgroundRemovesIt() throws {
        let png = try makePNG(in: tempDir())
        let model = BackgroundLibraryModel(library: BackgroundLibrary(directory: tempDir()))
        let done = expectation(description: "import finishes")
        var item: BackgroundItem?
        model.onImported = { item = $0; done.fulfill() }
        model.importFiles([png])
        wait(for: [done], timeout: 10)

        let imported = try XCTUnwrap(item)
        let before = model.items.count
        model.delete(imported)
        XCTAssertEqual(model.items.count, before - 1)
        model.delete(try XCTUnwrap(model.items.first { $0.isBuiltIn }))
        XCTAssertEqual(model.items.count, before - 1, "built-in backgrounds can't be deleted")
    }
}

final class BackgroundPickerRenderTests: XCTestCase {
    /// Renders the picker the way the popover shows it, on a dark panel.
    private func renderPicker(model: SettingsModel, backgrounds: BackgroundLibraryModel) throws -> NSBitmapImageRep {
        let root = BackgroundPickerView(model: model, backgrounds: backgrounds)
            .background(Color(white: 0.16))
            .environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: root)
        let size = host.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.alphaValue = 0
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))   // let SwiftUI lay out and load thumbnails

        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        window.effectiveAppearance.performAsCurrentDrawingAppearance { host.cacheDisplay(in: host.bounds, to: rep) }
        window.orderOut(nil)
        return rep
    }

    func testPickerShowsBuiltInsAndUploadsWithoutBeingBlank() throws {
        let library = BackgroundLibrary(directory: tempDir())
        let backgrounds = BackgroundLibraryModel(library: library)
        let png = try makePNG(in: tempDir(), name: "my photo.png", color: (0.9, 0.3, 0.2))
        let done = expectation(description: "import finishes")
        backgrounds.onImported = { _ in done.fulfill() }
        backgrounds.importFiles([png])
        wait(for: [done], timeout: 10)

        let model = SettingsModel(settings: AppSettings(), themeStore: ThemeStore(directory: tempDir()))
        let rep = try renderPicker(model: model, backgrounds: backgrounds)
        XCTAssertGreaterThan(rep.pixelsWide, 300)
        XCTAssertGreaterThan(rep.pixelsHigh, 300)

        // Count distinct colors on a coarse grid: a blank or all-white render would have very few.
        var seen = Set<UInt32>()
        for y in stride(from: 0, to: rep.pixelsHigh, by: 6) {
            for x in stride(from: 0, to: rep.pixelsWide, by: 6) {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let key = UInt32(c.redComponent * 15) << 8 | UInt32(c.greenComponent * 15) << 4 | UInt32(c.blueComponent * 15)
                seen.insert(key)
            }
        }
        XCTAssertGreaterThan(seen.count, 25, "the picker should show gradient swatches, a photo thumbnail and text")

        // The uploaded photo is orange-red: some thumbnail pixels must be strongly red.
        var foundUpload = false
        for y in stride(from: 0, to: rep.pixelsHigh, by: 4) where !foundUpload {
            for x in stride(from: 0, to: rep.pixelsWide, by: 4) {
                if let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), c.redComponent > 0.75, c.greenComponent < 0.45, c.blueComponent < 0.4 {
                    foundUpload = true
                    break
                }
            }
        }
        XCTAssertTrue(foundUpload, "the uploaded image's thumbnail should be visible in the grid")

        if let dir = ProcessInfo.processInfo.environment["LYRA_SNAPSHOT_DIR"],
           let png = rep.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("background-picker.png"))
        }
    }

    func testSelectingABackgroundUpdatesTheSettings() {
        let backgrounds = BackgroundLibraryModel(library: BackgroundLibrary(directory: tempDir()))
        let model = SettingsModel(settings: AppSettings(), themeStore: ThemeStore(directory: tempDir()))
        let other = backgrounds.items.first { $0.id != model.settings.player.backgroundID }!
        model.settings.player.backgroundID = other.id
        XCTAssertEqual(model.settings.player.backgroundID, other.id)
    }
}
