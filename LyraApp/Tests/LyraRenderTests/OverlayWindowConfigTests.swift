import XCTest
import AppKit
@testable import LyraRender

/// Pins the overlay window configuration that makes it appear over other apps' native full-screen Spaces.
/// Measured on macOS: under `.regular` activation policy a plain NSWindow is never shown in a full-screen
/// Space (any level); a borderless `.nonactivatingPanel` with canJoinAllSpaces + fullScreenAuxiliary is.
final class OverlayWindowConfigTests: XCTestCase {
    private func makeWindow(level: NSWindow.Level = .floating) -> OverlayWindow {
        OverlayWindow(frame: NSRect(x: 10, y: 20, width: 420, height: 109), level: level, content: NSView())
    }

    func testIsANonActivatingPanel() {
        let w = makeWindow()
        XCTAssertTrue((w as AnyObject) is NSPanel, "a plain NSWindow is not shown over full-screen apps in .regular policy")
        XCTAssertTrue(w.styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(w.styleMask.contains(.borderless))
        XCTAssertFalse(w.hidesOnDeactivate, "NSPanel hides on deactivate by default; the overlay must stay")
    }

    func testClickThroughAndNeverKey() {
        let w = makeWindow()
        XCTAssertTrue(w.ignoresMouseEvents)
        XCTAssertFalse(w.canBecomeKey)
        XCTAssertFalse(w.canBecomeMain)
        XCTAssertFalse(w.isOpaque)
        XCTAssertFalse(w.hasShadow)
        XCTAssertEqual(w.backgroundColor, .clear)
    }

    func testCollectionBehaviorFollowsUserIntoEverySpace() {
        let b = makeWindow().collectionBehavior
        for flag: NSWindow.CollectionBehavior in [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle] {
            XCTAssertTrue(b.contains(flag), "missing \(flag)")
        }
        XCTAssertFalse(b.contains(.moveToActiveSpace))
    }

    func testLevelsMatchTheSetting() {
        XCTAssertEqual(makeWindow(level: OverlayLevel.floating.windowLevel).level, .floating)
        XCTAssertEqual(makeWindow(level: OverlayLevel.aboveEverything.windowLevel).level, .screenSaver)
        XCTAssertGreaterThan(OverlayLevel.floating.windowLevel, OverlayLevel.desktop.windowLevel)
    }

    func testManagerBuildsPanelsAndAppliesLevelChanges() throws {
        let renderer = try metalRendererOrSkip()
        let manager = OverlayManager(renderer: renderer, itemsProvider: { _ in [] }, lightProvider: { _ in nil })
        manager.isVisible = false
        manager.allDisplays = false
        manager.rebuild()
        XCTAssertEqual(manager.overlayWindows.count, 1)
        XCTAssertTrue(manager.overlayWindows.allSatisfy { $0 is NSPanel && $0.ignoresMouseEvents && !$0.canBecomeKey })
        manager.level = .aboveEverything
        XCTAssertEqual(manager.overlayWindows.first?.level, .screenSaver)
    }
}

/// Render tests need a GPU; hosted CI machines may not have one, so they skip instead of failing.
func metalRendererOrSkip() throws -> MetalRenderer {
    guard let renderer = MetalRenderer() else { throw XCTSkip("no Metal device") }
    return renderer
}
