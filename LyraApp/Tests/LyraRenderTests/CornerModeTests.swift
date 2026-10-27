import XCTest
import AppKit
import Carbon.HIToolbox
import LyraCore
@testable import LyraRender

final class PanelRenderTests: XCTestCase {
    private func renderer() throws -> MetalRenderer { try metalRendererOrSkip() }

    /// RGBA bytes (premultiplied, BGRA order flattened to alpha only) at a pixel of a 1x render.
    private func alpha(_ image: CGImage, x: Int, y: Int) -> Int {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return Int(data[(y * w + x) * 4 + 3])
    }

    private let size = CGSize(width: 400, height: 200)

    private func panel(opacity: Float = 0.5, rect: CGRect = CGRect(x: 50, y: 40, width: 300, height: 120), radius: Double = 24) -> PanelParams {
        PanelParams(rect: rect, cornerRadius: radius, color: RGBA(0.05, 0.05, 0.1, opacity))
    }

    func testPanelFillsItsRectAtTheRequestedOpacityAndNothingOutside() throws {
        let image = try XCTUnwrap(renderer().renderOffscreen([], panel: panel(opacity: 0.5), size: size, scale: 1))
        XCTAssertEqual(alpha(image, x: 200, y: 100), 128, accuracy: 3, "inside: half opaque")
        XCTAssertEqual(alpha(image, x: 10, y: 10), 0, "outside the panel is untouched")
        XCTAssertEqual(alpha(image, x: 390, y: 190), 0)
        XCTAssertEqual(alpha(image, x: 200, y: 20), 0, "above the panel")
        XCTAssertEqual(alpha(image, x: 200, y: 180), 0, "below the panel")
    }

    func testCornersAreRounded() throws {
        let image = try XCTUnwrap(renderer().renderOffscreen([], panel: panel(radius: 30), size: size, scale: 1))
        XCTAssertEqual(alpha(image, x: 52, y: 42), 0, "the extreme corner pixel is cut away by the radius")
        XCTAssertGreaterThan(alpha(image, x: 200, y: 42), 100, "the middle of the top edge is filled")
        let square = try XCTUnwrap(renderer().renderOffscreen([], panel: panel(radius: 0), size: size, scale: 1))
        XCTAssertGreaterThan(alpha(square, x: 52, y: 42), 100, "with no radius the corner is filled")
    }

    func testOpacityScalesAndZeroDrawsNothing() throws {
        let r = try renderer()
        let strong = try XCTUnwrap(r.renderOffscreen([], panel: panel(opacity: 0.9), size: size, scale: 1))
        let weak = try XCTUnwrap(r.renderOffscreen([], panel: panel(opacity: 0.2), size: size, scale: 1))
        XCTAssertGreaterThan(alpha(strong, x: 200, y: 100), alpha(weak, x: 200, y: 100) + 100)
        let none = try XCTUnwrap(r.renderOffscreen([], panel: panel(opacity: 0), size: size, scale: 1))
        XCTAssertEqual(alpha(none, x: 200, y: 100), 0)
    }

    func testEdgesAreAntialiasedNotJagged() throws {
        let image = try XCTUnwrap(renderer().renderOffscreen([], panel: panel(opacity: 1, radius: 40), size: size, scale: 1))
        // The straight edges sit on whole pixels, so only a properly antialiased curve produces pixels that
        // are neither fully clear nor fully opaque. A hard-edged circle would give almost none.
        var partial = 0
        for y in 36..<84 { for x in 46..<94 { let a = alpha(image, x: x, y: y); if a > 8 && a < 247 { partial += 1 } } }
        XCTAssertGreaterThan(partial, 25, "the curved corner blends smoothly into the background")
    }

    func testTextDrawsOverThePanel() throws {
        let text = DrawItem(text: "MMMM", font: FontSpec(size: 70, weight: 0.5), center: CGPoint(x: 200, y: 100), size: CGSize(width: 250, height: 80),
                            baseColor: .white, highlightColor: .white, glowColor: .white, glow: 0, progress: 1, opacity: 1)
        let r = try renderer()
        let withPanel = try XCTUnwrap(r.renderOffscreen([text], panel: panel(opacity: 0.4), size: size, scale: 1))
        // On the panel the text is opaque white, so some pixels inside the text area are fully opaque.
        var opaque = 0
        for y in stride(from: 60, to: 140, by: 2) { for x in stride(from: 100, to: 300, by: 2) where alpha(withPanel, x: x, y: y) > 250 { opaque += 1 } }
        XCTAssertGreaterThan(opaque, 50, "text is drawn above the backdrop")
    }

    func testPanelUniformsMatchTheShaderLayout() {
        // float2 x3 (24 bytes) + 2 floats (8) + float4 (16, 16-aligned at 32) = 48 bytes.
        XCTAssertEqual(MemoryLayout<MetalRenderer.PanelUniforms>.stride, 48)
    }
}

final class GlobalHotKeyTests: XCTestCase {
    // A combination nothing real uses: control+option+command+shift with an F-key.
    private let keyCode = kVK_F18
    private let modifiers = controlKey | optionKey | cmdKey | shiftKey

    func testRegistersAndReleases() throws {
        var first: GlobalHotKey? = GlobalHotKey(keyCode: keyCode, modifiers: modifiers) {}
        XCTAssertNotNil(first)
        first = nil
        let again = GlobalHotKey(keyCode: keyCode, modifiers: modifiers) {}
        XCTAssertNotNil(again, "once released the combination can be registered again")
        _ = again
    }

    func testAnAlreadyTakenCombinationFailsCleanly() throws {
        let first = try XCTUnwrap(GlobalHotKey(keyCode: keyCode, modifiers: modifiers) {})
        XCTAssertNil(GlobalHotKey(keyCode: keyCode, modifiers: modifiers) {}, "a second registration of the same keys is refused")
        _ = first
    }
}

final class OverlayWindowFrameTests: XCTestCase {
    func testFramesFollowTheProviderWithoutRecreatingWindows() throws {
        let renderer = try metalRendererOrSkip()
        let manager = OverlayManager(renderer: renderer, itemsProvider: { _ in [] }, lightProvider: { _ in nil })
        manager.isVisible = false      // keep the windows off screen while testing
        manager.allDisplays = false
        manager.rebuild()
        let screen = try XCTUnwrap(NSScreen.screens.first)

        XCTAssertEqual(manager.windowFrames, [screen.frame], "by default the window covers the whole screen")

        var settings = CornerOverlaySettings()
        settings.enabled = true
        settings.corner = .topRight
        manager.frameProvider = { CornerOverlay.frame(in: $0.visibleFrame, settings: settings) }
        let before = manager.windowIdentities
        manager.relayout()
        let expected = CornerOverlay.frame(in: screen.visibleFrame, settings: settings)
        XCTAssertEqual(manager.windowFrames, [expected])
        XCTAssertEqual(manager.windowIdentities, before, "moving the card must not recreate the window")
        XCTAssertLessThan(expected.width, screen.frame.width / 2, "it really is a small card")

        settings.corner = .bottomLeft
        manager.relayout()
        XCTAssertEqual(manager.windowFrames, [CornerOverlay.frame(in: screen.visibleFrame, settings: settings)])

        manager.frameProvider = nil
        manager.relayout()
        XCTAssertEqual(manager.windowFrames, [screen.frame], "turning corner mode off restores the full screen")
    }
}
