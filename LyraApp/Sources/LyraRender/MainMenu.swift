import AppKit

/// The menu bar shown while Lyra is the active app. The status item's menu is separate.
enum MainMenu {
    static func build(target: AnyObject, openSettings: Selector, openPlayer: Selector, toggleFullScreen: Selector) -> NSMenu {
        let main = NSMenu()

        // Lyra menu
        let app = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Lyra", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.add("Settings…", openSettings, key: ",", target: target)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Lyra", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Lyra", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        app.submenu = appMenu
        main.addItem(app)

        // Player menu
        let player = NSMenuItem()
        let playerMenu = NSMenu(title: "Player")
        playerMenu.add("Open Player", openPlayer, key: "p", target: target)
        let full = playerMenu.add("Full Screen Player", toggleFullScreen, key: "f", target: target)
        full.keyEquivalentModifierMask = [.command, .control]
        player.submenu = playerMenu
        main.addItem(player)

        // Window menu
        let window = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        window.submenu = windowMenu
        main.addItem(window)
        NSApp.windowsMenu = windowMenu

        return main
    }
}

private extension NSMenu {
    @discardableResult
    func add(_ title: String, _ action: Selector, key: String, target: AnyObject) -> NSMenuItem {
        let item = addItem(withTitle: title, action: action, keyEquivalent: key)
        item.target = target
        return item
    }
}
