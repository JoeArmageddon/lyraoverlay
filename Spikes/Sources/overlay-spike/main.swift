// Spike: can a click-through window render above the lock screen?
// Uses private SkyLight symbols resolved at runtime with dlsym, so a missing
// symbol on a future macOS degrades to a normal overlay instead of a crash.
//
// Usage: overlay-spike [seconds] [--no-space]
//   Run it, then lock the screen (ctrl+cmd+Q) and look for the banner.

import AppKit

// MARK: - SkyLight backend

final class SkyLightBackend {
    typealias MainConn = @convention(c) () -> Int32
    // CGSSpaceID is size_t and the second SpaceCreate argument is a pointer,
    // so both must be 64-bit; 32-bit declarations leave garbage in the upper
    // register half on arm64.
    typealias SpaceCreate = @convention(c) (Int32, Int, CFDictionary?) -> Int
    typealias SetLevel = @convention(c) (Int32, Int, Int32) -> Int32
    typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Void
    typealias AddWindows = @convention(c) (Int32, CFArray, CFArray) -> Void

    private let handle: UnsafeMutableRawPointer?
    private static func sym<T>(_ h: UnsafeMutableRawPointer?, _ name: String, as: T.Type) -> T? {
        guard let h, let p = dlsym(h, name) else { return nil }
        return unsafeBitCast(p, to: T.self)
    }

    let mainConn: MainConn?
    let spaceCreate: SpaceCreate?
    let setLevel: SetLevel?
    let showSpaces: ShowSpaces?
    let addWindows: AddWindows?

    init() {
        let h = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
        handle = h
        mainConn = Self.sym(h, "SLSMainConnectionID", as: MainConn.self)
        spaceCreate = Self.sym(h, "SLSSpaceCreate", as: SpaceCreate.self)
        setLevel = Self.sym(h, "SLSSpaceSetAbsoluteLevel", as: SetLevel.self)
        showSpaces = Self.sym(h, "SLSShowSpaces", as: ShowSpaces.self)
        addWindows = Self.sym(h, "SLSAddWindowsToSpaces", as: AddWindows.self)
    }

    var report: String {
        """
        SkyLight loaded: \(handle != nil)
          SLSMainConnectionID      \(mainConn != nil)
          SLSSpaceCreate           \(spaceCreate != nil)
          SLSSpaceSetAbsoluteLevel \(setLevel != nil)
          SLSShowSpaces            \(showSpaces != nil)
          SLSAddWindowsToSpaces    \(addWindows != nil)
        """
    }

    var complete: Bool {
        mainConn != nil && spaceCreate != nil && setLevel != nil && showSpaces != nil && addWindows != nil
    }

    /// Moves `window` into a fresh space pinned at the maximum absolute level,
    /// which is what lets it draw over the lock screen.
    func elevate(_ window: NSWindow) -> Bool {
        guard complete, let mainConn, let spaceCreate, let setLevel, let showSpaces, let addWindows else {
            return false
        }
        let cid = mainConn()
        let space = spaceCreate(cid, 1, nil)
        print("  created space id \(space)")
        guard space != 0 else { return false }
        let rc = setLevel(cid, space, Int32.max)
        print("  SetAbsoluteLevel rc=\(rc)")
        showSpaces(cid, [space] as CFArray)
        addWindows(cid, [window.windowNumber] as CFArray, [space] as CFArray)
        return true
    }
}

// MARK: - Window

func makeOverlay(on screen: NSScreen) -> NSWindow {
    let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
    w.isOpaque = false
    w.backgroundColor = .clear
    w.hasShadow = false
    w.ignoresMouseEvents = true
    w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
    w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

    let label = NSTextField(labelWithString: "LYRA SPIKE: if you can read this on the lock screen, it works")
    label.font = .systemFont(ofSize: 34, weight: .heavy)
    label.textColor = .white
    label.alignment = .center
    label.wantsLayer = true
    label.layer?.backgroundColor = NSColor.systemPink.withAlphaComponent(0.85).cgColor
    label.layer?.cornerRadius = 16
    label.sizeToFit()
    label.frame = NSRect(
        x: (screen.frame.width - label.frame.width - 40) / 2,
        y: screen.frame.height * 0.2,
        width: label.frame.width + 40, height: label.frame.height + 20
    )
    let content = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
    content.addSubview(label)
    w.contentView = content
    return w
}

// MARK: - Main

let args = CommandLine.arguments.dropFirst()
let seconds = args.compactMap(Double.init).first ?? 120
let useSpace = !args.contains("--no-space")

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let backend = SkyLightBackend()
print(backend.report)

var windows: [NSWindow] = []
for screen in NSScreen.screens {
    let w = makeOverlay(on: screen)
    w.orderFrontRegardless()
    if useSpace {
        let ok = backend.elevate(w)
        print("Display \(screen.localizedName): windowNumber=\(w.windowNumber) elevated=\(ok)")
    } else {
        print("Display \(screen.localizedName): windowNumber=\(w.windowNumber) (no SkyLight, plain shielding level)")
    }
    windows.append(w)
}

// Diagnostics: you can't watch the screen while it is locked, so log what the
// window server says about our windows to overlay-spike.log every 2 seconds.
let logURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("overlay-spike.log")
try? "".write(to: logURL, atomically: true, encoding: .utf8)
func log(_ s: String) {
    let line = "\(ISO8601DateFormatter().string(from: Date())) \(s)\n"
    if let h = try? FileHandle(forWritingTo: logURL) {
        h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close()
    }
}
var locked = false
let dnc = DistributedNotificationCenter.default()
// The lock session may hide or reset our space, so re-apply the elevation on
// lock and keep re-asserting it while locked. Disable with --no-reassert.
let reassert = !args.contains("--no-reassert")
func reassertAll(_ why: String) {
    for w in windows {
        w.orderFrontRegardless()
        let ok = useSpace ? backend.elevate(w) : false
        log("reassert(\(why)) win=\(w.windowNumber) ok=\(ok)")
    }
}
var reassertTimer: Timer?
dnc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { _ in
    locked = true; log("EVENT screen locked")
    guard reassert else { return }
    for d in [0.2, 1.0] { DispatchQueue.main.asyncAfter(deadline: .now() + d) { reassertAll("lock+\(d)s") } }
    reassertTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in if locked { reassertAll("while-locked") } }
}
dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { _ in
    locked = false; log("EVENT screen unlocked")
    reassertTimer?.invalidate()
    if reassert { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { reassertAll("unlock") } }
}

Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
    let info = (CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]]) ?? []
    for w in windows {
        let entry = info.first { ($0[kCGWindowNumber as String] as? Int) == w.windowNumber }
        let layer = entry?[kCGWindowLayer as String] as? Int ?? -1
        let onScreen = entry?[kCGWindowIsOnscreen as String] as? Bool ?? false
        log("locked=\(locked) win=\(w.windowNumber) found=\(entry != nil) layer=\(layer) onScreen=\(onScreen) isVisible=\(w.isVisible) occluded=\(!w.occlusionState.contains(.visible))")
    }
}
log("started; skylight complete=\(backend.complete)")

print("Running for \(Int(seconds))s. Lock the screen now (ctrl+cmd+Q) and check for the pink banner.")
print("Diagnostics are written to \(logURL.path)")
DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
    print("Done.")
    NSApp.terminate(nil)
}
app.run()
