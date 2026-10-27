import Metal
import LyraCore

struct TextTexture {
    var texture: MTLTexture
    var pixelSize: SIMD2<Float>
    var textRange: SIMD2<Float>
}

/// Rasterized text as GPU textures, keyed by text, font and scale. Main-thread only,
/// like the draw calls that use it.
final class TextureCache {
    private struct Key: Hashable {
        var text: String
        var family: String
        var size: Double
        var weight: Double
        var tracking: Double
        var italic: Bool
        var scale: Double
    }

    private let device: MTLDevice
    private var entries: [Key: TextTexture] = [:]
    private var order: [Key] = []
    private let capacity: Int

    init(device: MTLDevice, capacity: Int = 400) {
        self.device = device
        self.capacity = capacity
    }

    var count: Int { entries.count }

    func texture(for text: String, font: FontSpec, scale: CGFloat) -> TextTexture? {
        // Round so tiny float differences in size don't create a texture per frame.
        let key = Key(text: text, family: font.family, size: (font.size * 2).rounded() / 2,
                      weight: (font.weight * 100).rounded() / 100,
                      tracking: (font.tracking * 1000).rounded() / 1000, italic: font.italic, scale: Double(scale))
        if let hit = entries[key] { return hit }

        var spec = font
        spec.size = key.size
        guard let raster = TextRasterizer.rasterize(text, font: spec, scale: scale) else { return nil }

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: raster.pixelWidth, height: raster.pixelHeight, mipmapped: false)
        desc.usage = .shaderRead
        guard let tex = device.makeTexture(descriptor: desc) else { return nil }
        raster.pixels.withUnsafeBytes { buf in
            tex.replace(region: MTLRegionMake2D(0, 0, raster.pixelWidth, raster.pixelHeight),
                        mipmapLevel: 0, withBytes: buf.baseAddress!, bytesPerRow: raster.pixelWidth * 4)
        }

        let entry = TextTexture(
            texture: tex,
            pixelSize: SIMD2(Float(raster.pixelWidth), Float(raster.pixelHeight)),
            textRange: SIMD2(raster.textStartU, raster.textEndU))
        entries[key] = entry
        order.append(key)
        if order.count > capacity {
            let evict = order.prefix(order.count - capacity)
            for k in evict { entries[k] = nil }
            order.removeFirst(evict.count)
        }
        return entry
    }
}
