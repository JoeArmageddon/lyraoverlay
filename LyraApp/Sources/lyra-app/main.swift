// Lyra desktop overlay.
//
//   lyra-app                       run as a menu bar app
//   lyra-app --render-test out.png render sample lyric frames to a PNG and exit (no screen access needed)
//   lyra-app --render-lights out.png  render edge-lighting samples to a PNG and exit
//   lyra-app --render-styles out.png  render every lyric style, one per row, to a PNG and exit
//   lyra-app --render-animations out.png  render every entrance animation, one per row, frozen at 35%, to a PNG and exit
//   lyra-app --render-cinema out.png  render the film-look stages (bars, vignette, grain, flare) side by side to a PNG and exit
//   lyra-app --render-cinematic out.png  render 12 consecutive Cinematic shots plus one transition to a PNG and exit
//   lyra-app --render-settings <tab> out.png  render a settings tab (themes, lyrics, lights, general) to a PNG and exit

import AppKit
import LyraCore
import LyraRender

let args = Array(CommandLine.arguments.dropFirst())

if let flag = args.firstIndex(of: "--render-test") {
    guard flag + 1 < args.count else {
        FileHandle.standardError.write(Data("usage: lyra-app --render-test <out.png>\n".utf8))
        exit(2)
    }
    guard let renderer = MetalRenderer(),
          let image = SnapshotSheet.render(renderer: renderer),
          SnapshotSheet.writePNG(image, to: URL(fileURLWithPath: args[flag + 1])) else {
        FileHandle.standardError.write(Data("render failed\n".utf8))
        exit(1)
    }
    print("wrote \(args[flag + 1]) (\(image.width)x\(image.height))")
    exit(0)
}

if let flag = args.firstIndex(of: "--render-lights") {
    guard flag + 1 < args.count else {
        FileHandle.standardError.write(Data("usage: lyra-app --render-lights <out.png>\n".utf8))
        exit(2)
    }
    guard let renderer = MetalRenderer(),
          let image = SnapshotSheet.renderLights(renderer: renderer),
          SnapshotSheet.writePNG(image, to: URL(fileURLWithPath: args[flag + 1])) else {
        FileHandle.standardError.write(Data("render failed\n".utf8))
        exit(1)
    }
    print("wrote \(args[flag + 1]) (\(image.width)x\(image.height))")
    exit(0)
}

if let flag = args.firstIndex(of: "--render-styles") {
    guard flag + 1 < args.count else {
        FileHandle.standardError.write(Data("usage: lyra-app --render-styles <out.png>\n".utf8))
        exit(2)
    }
    guard let renderer = MetalRenderer(),
          let image = StyleSheet.render(renderer: renderer),
          SnapshotSheet.writePNG(image, to: URL(fileURLWithPath: args[flag + 1])) else {
        FileHandle.standardError.write(Data("render failed\n".utf8))
        exit(1)
    }
    print("wrote \(args[flag + 1]) (\(image.width)x\(image.height))")
    exit(0)
}

if let flag = args.firstIndex(of: "--render-settings") {
    guard flag + 2 < args.count else {
        FileHandle.standardError.write(Data("usage: lyra-app --render-settings <themes|lyrics|lights|general> <out.png>\n".utf8))
        exit(2)
    }
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let ok = AppController().snapshotSettings(tab: args[flag + 1], to: URL(fileURLWithPath: args[flag + 2]))
    print(ok ? "wrote \(args[flag + 2])" : "render failed")
    exit(ok ? 0 : 1)
}

if let flag = args.firstIndex(of: "--show-settings") {
    // Shows the real settings window (for screenshots of it), then keeps running like the app.
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let controller = AppController()
    controller.showSettings(tab: flag + 1 < args.count ? args[flag + 1] : "themes")
    app.run()
}

if let flag = args.firstIndex(of: "--render-animations") {
    guard flag + 1 < args.count else {
        FileHandle.standardError.write(Data("usage: lyra-app --render-animations <out.png>\n".utf8))
        exit(2)
    }
    guard let renderer = MetalRenderer(),
          let image = AnimationSheet.render(renderer: renderer),
          SnapshotSheet.writePNG(image, to: URL(fileURLWithPath: args[flag + 1])) else {
        FileHandle.standardError.write(Data("render failed\n".utf8))
        exit(1)
    }
    print("wrote \(args[flag + 1]) (\(image.width)x\(image.height))")
    exit(0)
}

if let flag = args.firstIndex(of: "--show-player") {
    // Shows the real player window, for screenshots: `--show-player [backgroundID] [--library <dir>]`.
    // It never touches the saved settings, and a custom library folder keeps test uploads out of the real one.
    setenv("LYRA_NO_FRAME_AUTOSAVE", "1", 1)
    var settings = AppSettings()
    if flag + 1 < args.count, !args[flag + 1].hasPrefix("--") { settings.player.backgroundID = args[flag + 1] }
    // `--cinema` turns on the film look (bars, vignette, grain, flare) for this run only.
    if args.contains("--cinema") {
        settings.player.cinema.enabled = true
        settings.player.cinema.vignette = 0.5
        settings.player.cinema.grain = 0.2
        settings.player.cinema.flare = 0.7
    }
    var library = BackgroundLibrary()
    if let lib = args.firstIndex(of: "--library"), lib + 1 < args.count {
        library = BackgroundLibrary(directory: URL(fileURLWithPath: args[lib + 1]))
    }
    // `--import <file>` (repeatable, and only with `--library`) adds files to that library and shows the last one.
    for (i, arg) in args.enumerated() where arg == "--import" && i + 1 < args.count {
        guard args.contains("--library") else {
            FileHandle.standardError.write(Data("--import needs --library <dir>, so the real library is never touched\n".utf8))
            exit(2)
        }
        do {
            settings.player.backgroundID = try library.importFile(from: URL(fileURLWithPath: args[i + 1])).id
        } catch {
            FileHandle.standardError.write(Data("import failed: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
    guard let renderer = MetalRenderer() else { exit(1) }
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let session = LyricsSession()
    session.start()
    let capture = SystemAudioCapture()
    Task { await capture.start() }
    let player = PlayerWindowController(renderer: renderer, model: SettingsModel(settings: settings), session: session,
                                        capture: capture, library: library)
    player.show()
    app.run()
}

if let flag = args.firstIndex(of: "--render-cinema") {
    guard flag + 1 < args.count else {
        FileHandle.standardError.write(Data("usage: lyra-app --render-cinema <out.png>\n".utf8))
        exit(2)
    }
    guard let renderer = MetalRenderer(),
          let image = CinemaSheet.render(renderer: renderer),
          SnapshotSheet.writePNG(image, to: URL(fileURLWithPath: args[flag + 1])) else {
        FileHandle.standardError.write(Data("render failed\n".utf8))
        exit(1)
    }
    print("wrote \(args[flag + 1]) (\(image.width)x\(image.height))")
    exit(0)
}

if let flag = args.firstIndex(of: "--render-cinematic") {
    guard flag + 1 < args.count else {
        FileHandle.standardError.write(Data("usage: lyra-app --render-cinematic <out.png>\n".utf8))
        exit(2)
    }
    guard let renderer = MetalRenderer(),
          let image = CinematicSheet.render(renderer: renderer),
          SnapshotSheet.writePNG(image, to: URL(fileURLWithPath: args[flag + 1])) else {
        FileHandle.standardError.write(Data("render failed\n".utf8))
        exit(1)
    }
    print("wrote \(args[flag + 1]) (\(image.width)x\(image.height))")
    exit(0)
}

if let flag = args.firstIndex(of: "--render-corner") {
    guard flag + 1 < args.count else {
        FileHandle.standardError.write(Data("usage: lyra-app --render-corner <out.png>\n".utf8))
        exit(2)
    }
    guard let renderer = MetalRenderer(),
          let image = CornerSheet.render(renderer: renderer),
          SnapshotSheet.writePNG(image, to: URL(fileURLWithPath: args[flag + 1])) else {
        FileHandle.standardError.write(Data("render failed\n".utf8))
        exit(1)
    }
    print("wrote \(args[flag + 1]) (\(image.width)x\(image.height))")
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)   // a normal app: Dock icon, main menu, and the menu bar item as well
let controller = AppController()
controller.start()
if args.contains("--cinematic-demo") {
    // Cinematic style plus film look in the player, for this run only (never saved).
    controller.showCinematicDemo()
}
if let flag = args.firstIndex(of: "--corner-demo") {
    // Shows corner mode for this run only (never saved). Optional corner: topLeft, topRight, bottomLeft, bottomRight.
    let corner = flag + 1 < args.count ? ScreenCorner(rawValue: args[flag + 1]) : nil
    controller.showCornerDemo(corner: corner ?? .bottomRight)
}
if let flag = args.firstIndex(of: "--overlay-demo") {
    // Forces the overlay on with a fixed sample line, no music needed: `--overlay-demo [full|corner]`. Never saved.
    let mode = flag + 1 < args.count ? args[flag + 1] : "full"
    controller.showOverlayDemo(corner: mode == "corner")
}
if args.contains("--fullscreen-demo") {
    // For checking native full screen without clicking: in after 3 s, back out after 10 s.
    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { controller.toggleFullScreen() }
    DispatchQueue.main.asyncAfter(deadline: .now() + 10) { controller.toggleFullScreen() }
}
app.run()
