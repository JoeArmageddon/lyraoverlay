import AppKit
import SwiftUI

/// Owns the settings window. The app has no Dock icon, so showing it also activates the app.
final class SettingsWindowController: NSWindowController {
    init(model: SettingsModel, renderer: MetalRenderer, initialTab: String = "themes") {
        let view = SettingsView(model: model, preview: PreviewRenderer(renderer: renderer),
                                initialTab: SettingsView.Tab(rawValue: initialTab) ?? .themes)
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Lyra Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 700, height: 760))
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
