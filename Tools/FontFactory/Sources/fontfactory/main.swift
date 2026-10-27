// Generates Lyra's original fonts.
//
//   fontfactory --out Fonts [--specimens Fonts/specimens] [--only "Forge"]
//
// Writes one .ttf per style and, with --specimens, a CoreText-rendered specimen PNG per font so
// the result can be judged by eye. Nothing here touches the network.

import Foundation
import AppKit
import CoreText
import FontFactoryCore

var outDir = "Fonts"
var specimenDir: String?
var only: String?
var overviewPath: String?

var it = CommandLine.arguments.dropFirst().makeIterator()
while let arg = it.next() {
    switch arg {
    case "--out": outDir = it.next() ?? outDir
    case "--specimens": specimenDir = it.next()
    case "--only": only = it.next()
    case "--overview": overviewPath = it.next()
    default:
        FileHandle.standardError.write(Data("unknown argument \(arg)\nusage: fontfactory --out <dir> [--specimens <dir>] [--only <style name>]\n".utf8))
        exit(2)
    }
}

let fm = FileManager.default
try fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)
if let specimenDir { try fm.createDirectory(atPath: specimenDir, withIntermediateDirectories: true) }

// MARK: - Specimen

func specimen(fontURL: URL, postScriptName: String, title: String, to path: String) {
    CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)
    let width = 1600, height = 1060
    guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return }
    ctx.setFillColor(CGColor(red: 0.06, green: 0.06, blue: 0.08, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

    func draw(_ text: String, size: CGFloat, fontName: String, color: CGColor, y: inout CGFloat) {
        let font = CTFontCreateWithName(fontName as CFString, size, nil)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(cgColor: color) ?? .white]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
        y -= size * 1.18
        ctx.textPosition = CGPoint(x: 48, y: y)
        CTLineDraw(line, ctx)
        y -= size * 0.12
    }

    let white = CGColor(red: 0.96, green: 0.96, blue: 0.98, alpha: 1)
    let dim = CGColor(red: 0.55, green: 0.57, blue: 0.62, alpha: 1)
    var y = CGFloat(height) - 24
    draw("\(title)  \(postScriptName)", size: 20, fontName: "Helvetica", color: dim, y: &y)
    draw("ABCDEFGHIJKLMNOPQRSTUVWXYZ", size: 74, fontName: postScriptName, color: white, y: &y)
    draw("abcdefghijklmnopqrstuvwxyz", size: 62, fontName: postScriptName, color: white, y: &y)
    draw("0123456789  .,!?'\"-:;&()/#@%+=$*_~^<>[]{}|", size: 58, fontName: postScriptName, color: white, y: &y)
    draw("Midnight in the neon rain", size: 104, fontName: postScriptName, color: white, y: &y)
    draw("The quick brown fox jumps over the lazy dog", size: 38, fontName: postScriptName, color: white, y: &y)
    draw("ÀÉÎÕÜ àéîõü ñç åÿ ÅÇÑ  O0 I1 S5 B8 Z2 G6", size: 58, fontName: postScriptName, color: white, y: &y)
    draw("Every window holds a story to tell", size: 24, fontName: postScriptName, color: white, y: &y)

    guard let image = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

// MARK: - Run

for style in Styles.all where only == nil || only == style.name {
    let result = FontFactory.make(style)
    let url = URL(fileURLWithPath: outDir).appendingPathComponent(style.fileName)
    try result.data.write(to: url, options: .atomic)
    let missing = result.missing.isEmpty ? "" : "  MISSING: \(String(result.missing))"
    print("\(style.family): \(result.glyphCount) glyphs, \(result.data.count / 1024) KB -> \(url.path)\(missing)")
    if let specimenDir {
        specimen(fontURL: url, postScriptName: style.postScriptName, title: style.family,
                 to: URL(fileURLWithPath: specimenDir).appendingPathComponent(style.name.replacingOccurrences(of: " ", with: "") + ".png").path)
    }
}

// MARK: - Overview sheet: every font on one page, to compare them side by side.

func overview(styles: [StyleParams], fontsDir: String, to path: String) {
    let rowHeight = 228
    let width = 1500, height = rowHeight * styles.count + 20
    guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return }
    ctx.setFillColor(CGColor(red: 0.06, green: 0.06, blue: 0.08, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    func text(_ s: String, _ name: String, _ size: CGFloat, _ color: NSColor, x: CGFloat, y: CGFloat) {
        let font = CTFontCreateWithName(name as CFString, size, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color]))
        ctx.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, ctx)
    }
    for (i, style) in styles.enumerated() {
        let url = URL(fileURLWithPath: fontsDir).appendingPathComponent(style.fileName)
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        let top = CGFloat(height - 20 - i * rowHeight)
        text(style.family, "Helvetica", 18, NSColor(white: 0.55, alpha: 1), x: 36, y: top - 22)
        text("Midnight in the neon rain", style.postScriptName, 84, .white, x: 36, y: top - 108)
        text("THE QUICK BROWN FOX JUMPS OVER THE LAZY DOG 0123456789", style.postScriptName, 30, .white, x: 36, y: top - 154)
        text("O0 I1 S5 B8 D Q G6 Z2 U V  Hello!", style.postScriptName, 56, NSColor(white: 0.85, alpha: 1), x: 36, y: top - 207)
    }
    guard let image = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
    print("overview -> \(path)")
}

if let overviewPath {
    overview(styles: Styles.all.filter { only == nil || only == $0.name }, fontsDir: outDir, to: overviewPath)
}
