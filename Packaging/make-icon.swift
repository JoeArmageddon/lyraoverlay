// Draws the Lyra app icon with CoreGraphics and writes a full .iconset folder.
//
//   make-icon <output.iconset>
//
// Each size is drawn directly from vector shapes (not scaled down from one big image), so small
// sizes stay crisp. `make-app.sh` turns the folder into AppIcon.icns with `iconutil`.

import CoreGraphics
import Foundation
import ImageIO

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [r, g, b, a])!
}

func roundedRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

/// Draws the icon into a square canvas of `size` pixels.
func drawIcon(_ ctx: CGContext, size: CGFloat) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let s = size / 1024   // all coordinates below are in a 1024 design grid

    ctx.saveGState()
    ctx.scaleBy(x: s, y: s)

    // macOS icon grid: the shape fills 824 of 1024 points, leaving room for the system shadow.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let corner: CGFloat = 185
    let tilePath = roundedRect(tile, radius: corner)

    // Soft drop shadow under the tile.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: rgb(0, 0, 0, 0.35))
    ctx.addPath(tilePath)
    ctx.setFillColor(rgb(0.1, 0.05, 0.25))
    ctx.fillPath()
    ctx.restoreGState()

    // Background: deep indigo to violet to hot pink, top-left to bottom-right.
    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    let background = CGGradient(colorsSpace: space, colors: [
        rgb(0.07, 0.05, 0.28), rgb(0.33, 0.12, 0.62), rgb(0.93, 0.28, 0.55),
    ] as CFArray, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(background, start: CGPoint(x: tile.minX, y: tile.maxY), end: CGPoint(x: tile.maxX, y: tile.minY), options: [])

    // A warm bloom behind the lyric lines.
    let bloom = CGGradient(colorsSpace: space, colors: [rgb(1, 0.75, 0.45, 0.55), rgb(1, 0.75, 0.45, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(bloom, startCenter: CGPoint(x: 512, y: 520), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 520), endRadius: 430, options: [])

    // Edge light: a glowing rim hugging the inside of the tile, like the app's edge lighting.
    ctx.setStrokeColor(rgb(1, 0.9, 1, 0.9))
    ctx.setLineWidth(10)
    ctx.setShadow(offset: .zero, blur: 40, color: rgb(1, 0.55, 0.95, 1))
    ctx.addPath(roundedRect(tile.insetBy(dx: 5, dy: 5), radius: corner - 5))
    ctx.strokePath()
    ctx.restoreGState()

    // Three lyric lines: the first is mid-sweep, with the sung part bright and the rest dim.
    let lines: [(y: CGFloat, width: CGFloat, alpha: CGFloat)] = [(600, 540, 1.0), (500, 420, 0.5), (400, 300, 0.32)]
    let barHeight: CGFloat = 54
    let left: CGFloat = 512 - 540 / 2
    for (index, line) in lines.enumerated() {
        let x = 512 - line.width / 2
        let rect = CGRect(x: x, y: line.y, width: line.width, height: barHeight)
        let bar = roundedRect(rect, radius: barHeight / 2)

        ctx.saveGState()
        ctx.addPath(bar)
        ctx.clip()
        // Unsung base.
        ctx.setFillColor(rgb(1, 1, 1, index == 0 ? 0.32 : line.alpha * 0.55))
        ctx.fill(rect)
        if index == 0 {
            // Sung part: bright, with the boundary glowing.
            let sungWidth = line.width * 0.6
            ctx.setShadow(offset: .zero, blur: 36, color: rgb(1, 0.8, 1, 1))
            ctx.setFillColor(rgb(1, 1, 1, 1))
            ctx.fill(CGRect(x: x, y: line.y, width: sungWidth, height: barHeight))
        }
        ctx.restoreGState()
    }

    // The sweep marker: a thin glowing vertical line at the boundary of the sung part.
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 30, color: rgb(1, 0.85, 1, 1))
    ctx.setFillColor(rgb(1, 1, 1, 1))
    let markerX = left + 540 * 0.6 - 5
    ctx.addPath(roundedRect(CGRect(x: markerX, y: 575, width: 10, height: 104), radius: 5))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.restoreGState()
}

func writePNG(size: Int, to url: URL) throws {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
          // Never leave the transparent corners dirty.
          true else { throw NSError(domain: "icon", code: 1) }
    ctx.clear(CGRect(x: 0, y: 0, width: size, height: size))
    ctx.interpolationQuality = .high
    ctx.setAllowsAntialiasing(true)
    drawIcon(ctx, size: CGFloat(size))

    guard let image = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        throw NSError(domain: "icon", code: 2)
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { throw NSError(domain: "icon", code: 3) }
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: make-icon <output.iconset>\n".utf8))
    exit(2)
}
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

// The names `iconutil` expects: each point size at 1x and 2x.
let files: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
for file in files {
    do {
        try writePNG(size: file.pixels, to: directory.appendingPathComponent(file.name))
    } catch {
        FileHandle.standardError.write(Data("failed to write \(file.name): \(error)\n".utf8))
        exit(1)
    }
}
print("wrote \(files.count) icon sizes to \(directory.path)")
