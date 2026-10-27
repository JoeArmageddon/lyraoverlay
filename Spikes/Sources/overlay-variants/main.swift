// Spike: try several SkyLight configurations at once to see which, if any,
// draws over the lock screen. Each variant is a small colored banner at its own
// height, labeled V1..V4. Lock the screen once and note which banners appear.
//
// Usage: overlay-variants [seconds]

import AppKit

typealias CID = Int32

final class SL {
    private let h = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    private func sym<T>(_ n: String, _ t: T.Type) -> T? {
        guard let h, let p = dlsym(h, n) else { return nil }
        return unsafeBitCast(p, to: T.self)
    }
    lazy var mainConn = sym("SLSMainConnectionID", (@convention(c) () -> CID).self)
    lazy var spaceCreate = sym("SLSSpaceCreate", (@convention(c) (CID, Int, CFDictionary?) -> Int).self)
    lazy var spaceSetLevel = sym("SLSSpaceSetAbsoluteLevel", (@convention(c) (CID, Int, Int32) -> Int32).self)
    lazy var spaceSetType = sym("SLSSpaceSetType", (@convention(c) (CID, Int, Int32) -> Int32).self)
    lazy var showSpaces = sym("SLSShowSpaces", (@convention(c) (CID, CFArray) -> Void).self)
    lazy var addWindows = sym("SLSAddWindowsToSpaces", (@convention(c) (CID, CFArray, CFArray) -> Void).self)
    lazy var winSetLevel = sym("SLSSetWindowLevel", (@convention(c) (CID, UInt32, Int32) -> Int32).self)
    lazy var winSetSubLevel = sym("SLSSetWindowSubLevel", (@convention(c) (CID, UInt32, Int32) -> Int32).self)
    lazy var winSetTags = sym("SLSSetWindowTags", (@convention(c) (CID, UInt32, UnsafePointer<UInt64>, Int32) -> Int32).self)
    lazy var winOrder = sym("SLSOrderWindow", (@convention(c) (CID, UInt32, Int32, UInt32) -> Int32).self)

    /// Creates a space of `type` at `level` and moves the window into it.
    func putInSpace(_ w: NSWindow, type: Int32?, level: Int32) -> String {
        guard let mainConn, let spaceCreate, let spaceSetLevel, let showSpaces, let addWindows else { return "missing symbols" }
        let cid = mainConn()
        let s = spaceCreate(cid, 1, nil)
        var out = "space=\(s)"
        if let type, let spaceSetType { out += " setType(\(type))=\(spaceSetType(cid, s, type))" }
        out += " setLevel(\(level))=\(spaceSetLevel(cid, s, level))"
        showSpaces(cid, [s] as CFArray)
        addWindows(cid, [w.windowNumber] as CFArray, [s] as CFArray)
        return out
    }
    func setWindowLevel(_ w: NSWindow, level: Int32, sub: Int32? = nil) -> String {
        guard let mainConn, let winSetLevel else { return "missing symbols" }
        let cid = mainConn(), wid = UInt32(w.windowNumber)
        var out = "winLevel=\(winSetLevel(cid, wid, level))"
        if let sub, let winSetSubLevel { out += " subLevel(\(sub))=\(winSetSubLevel(cid, wid, sub))" }

        return out
    }
    func setTags(_ w: NSWindow, _ bits: UInt64) -> String {
        guard let mainConn, let winSetTags else { return "missing symbols" }
        var tags = bits
        return "tags(\(String(bits, radix: 16)))=\(winSetTags(mainConn(), UInt32(w.windowNumber), &tags, 64))"
    }
}

let sl = SL()
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

func banner(_ text: String, color: NSColor, row: Int) -> NSWindow {
    let screen = NSScreen.main!
    let size = NSSize(width: 760, height: 70)
    let origin = NSPoint(x: (screen.frame.width - size.width) / 2, y: screen.frame.height * 0.15 + CGFloat(row) * 90)
    let w = NSWindow(contentRect: NSRect(origin: origin, size: size), styleMask: .borderless, backing: .buffered, defer: false)
    w.isOpaque = false
    w.backgroundColor = color
    w.hasShadow = false
    w.ignoresMouseEvents = true
    w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
    w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    let label = NSTextField(labelWithString: text)
    label.font = .systemFont(ofSize: 26, weight: .heavy)
    label.textColor = .white
    label.frame = NSRect(x: 20, y: 18, width: size.width - 40, height: 36)
    w.contentView = NSView(frame: NSRect(origin: .zero, size: size))
    w.contentView?.addSubview(label)
    w.orderFrontRegardless()
    return w
}

// Tag bits seen in SkyLight users: sticky (1<<11), no-shadow (1<<3), and the
// high "system" style bits. These are guesses worth one test, not documented.
let stickyNoShadow: UInt64 = (1 << 11) | (1 << 3)
let systemBits: UInt64 = (1 << 11) | (1 << 3) | (1 << 40) | (1 << 41)

struct Variant { let name: String; let color: NSColor; let apply: (NSWindow) -> String }
let variants: [Variant] = [
    Variant(name: "V1 system space (type 2), max level", color: .systemRed) { w in
        sl.putInSpace(w, type: 2, level: Int32.max)
    },
    Variant(name: "V2 system space + tags + sublevel", color: .systemBlue) { w in
        sl.putInSpace(w, type: 2, level: Int32.max) + " " + sl.setTags(w, systemBits) + " " + sl.setWindowLevel(w, level: Int32.max - 16, sub: 100)
    },
    Variant(name: "V3 no space, window-level only + tags", color: .systemGreen) { w in
        sl.setTags(w, stickyNoShadow) + " " + sl.setWindowLevel(w, level: Int32.max - 16, sub: 100)
    },
    Variant(name: "V4 system space, lower level 100000", color: .systemOrange) { w in
        sl.putInSpace(w, type: 2, level: 100_000)
    },
]

let secs = CommandLine.arguments.dropFirst().compactMap(Double.init).first ?? 120
let logURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("overlay-variants.log")
try? "".write(to: logURL, atomically: true, encoding: .utf8)
func log(_ s: String) {
    print(s)
    let line = "\(ISO8601DateFormatter().string(from: Date())) \(s)\n"
    if let h = try? FileHandle(forWritingTo: logURL) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
}

var windows: [(Variant, NSWindow)] = []
for (i, v) in variants.enumerated() {
    let w = banner(v.name, color: v.color, row: i)
    let r = v.apply(w)
    log("\(v.name): win=\(w.windowNumber) \(r)")
    windows.append((v, w))
}

var locked = false
let dnc = DistributedNotificationCenter.default()
dnc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { _ in locked = true; log("EVENT locked") }
dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { _ in locked = false; log("EVENT unlocked") }

Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
    let info = (CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]]) ?? []
    for (v, w) in windows {
        let e = info.first { ($0[kCGWindowNumber as String] as? Int) == w.windowNumber }
        log("locked=\(locked) \(v.name.prefix(2)) found=\(e != nil) layer=\(e?[kCGWindowLayer as String] as? Int ?? -1) onScreen=\(e?[kCGWindowIsOnscreen as String] as? Bool ?? false) occluded=\(!w.occlusionState.contains(.visible))")
    }
}

print("Showing 4 banners (V1 red, V2 blue, V3 green, V4 orange) for \(Int(secs))s.")
print("Lock the screen (ctrl+cmd+Q), stay locked ~15s, and note which colors you can see. Log: \(logURL.path)")
DispatchQueue.main.asyncAfter(deadline: .now() + secs) { NSApp.terminate(nil) }
app.run()
