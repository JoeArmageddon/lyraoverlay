import Metal
import CoreGraphics
import LyraCore

/// Draws `DrawItem`s as tinted text quads. Shared by the on-screen views and the
/// offscreen path used for tests and snapshots.
public final class MetalRenderer {
    /// Must match `Uniforms` in Shaders.swift field for field.
    struct Uniforms {
        var viewport: SIMD2<Float>
        var center: SIMD2<Float>
        var quadSize: SIMD2<Float>
        var textRange: SIMD2<Float>
        var base: SIMD4<Float>
        var highlight: SIMD4<Float>
        var glowColor: SIMD4<Float>
        var progress: Float
        var glow: Float
        var opacity: Float
        var glowRadius: Float
        var texel: SIMD2<Float>
        var shadow: Float
        var blur: Float
    }

    /// Must match `RimUniforms` in Shaders.swift field for field.
    struct RimUniforms {
        var viewport: SIMD2<Float>
        var rectOrigin: SIMD2<Float>
        var rectSize: SIMD2<Float>
        var thickness: Float
        var radius: Float
        var primary: SIMD4<Float>
        var secondary: SIMD4<Float>
        var intensity: Float
        var phase: Float
    }

    /// Must match `CinemaUniforms` in Shaders.swift field for field.
    struct CinemaUniforms {
        var viewport: SIMD2<Float>
        var rectOrigin: SIMD2<Float>
        var rectSize: SIMD2<Float>
        var pictureOrigin: SIMD2<Float>
        var pictureSize: SIMD2<Float>
        var flareCenter: SIMD2<Float>
        var flareHalfWidth: Float
        var flare: Float
        var vignette: Float
        var grain: Float
        var seed: Float
        var cell: Float
        var scale: Float
        var pad: Float = 0
    }

    /// The finishing passes, in the order they are drawn.
    enum CinemaPass: Equatable { case flare, vignette, grain, bars }

    /// Must match `PanelUniforms` in Shaders.swift field for field.
    struct PanelUniforms {
        var viewport: SIMD2<Float>
        var center: SIMD2<Float>
        var halfSize: SIMD2<Float>
        var radius: Float
        var edge: Float
        var color: SIMD4<Float>
    }

    public static let pixelFormat: MTLPixelFormat = .bgra8Unorm

    let device: MTLDevice
    let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let rimPipeline: MTLRenderPipelineState
    private let flarePipeline: MTLRenderPipelineState
    private let vignettePipeline: MTLRenderPipelineState
    private let grainPipeline: MTLRenderPipelineState
    private let barPipeline: MTLRenderPipelineState
    private let panelPipeline: MTLRenderPipelineState
    private let sampler: MTLSamplerState
    let textures: TextureCache

    public init?(device: MTLDevice? = MTLCreateSystemDefaultDevice()) {
        guard let device, let queue = device.makeCommandQueue() else { return nil }
        do {
            let library = try device.makeLibrary(source: Shaders.source, options: nil)
            func makePipeline(vertex: String, fragment: String, additive: Bool = false) throws -> MTLRenderPipelineState {
                let desc = MTLRenderPipelineDescriptor()
                desc.vertexFunction = library.makeFunction(name: vertex)
                desc.fragmentFunction = library.makeFunction(name: fragment)
                let color = desc.colorAttachments[0]!
                color.pixelFormat = Self.pixelFormat
                // Premultiplied alpha: the fragment shaders already multiplied color by alpha.
                color.isBlendingEnabled = true
                color.sourceRGBBlendFactor = .one
                color.destinationRGBBlendFactor = additive ? .one : .oneMinusSourceAlpha
                color.sourceAlphaBlendFactor = .one
                color.destinationAlphaBlendFactor = additive ? .one : .oneMinusSourceAlpha
                return try device.makeRenderPipelineState(descriptor: desc)
            }
            self.pipeline = try makePipeline(vertex: "lyric_vertex", fragment: "lyric_fragment")
            self.rimPipeline = try makePipeline(vertex: "rim_vertex", fragment: "rim_fragment")
            // The flare adds light to what is already there; the rest blend normally.
            self.flarePipeline = try makePipeline(vertex: "cinema_vertex", fragment: "flare_fragment", additive: true)
            self.vignettePipeline = try makePipeline(vertex: "cinema_vertex", fragment: "vignette_fragment")
            self.grainPipeline = try makePipeline(vertex: "cinema_vertex", fragment: "grain_fragment")
            self.barPipeline = try makePipeline(vertex: "cinema_vertex", fragment: "bar_fragment")
            self.panelPipeline = try makePipeline(vertex: "panel_vertex", fragment: "panel_fragment")
        } catch {
            NSLog("Lyra: Metal pipeline failed: \(error)")
            return nil
        }
        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .linear
        samplerDesc.magFilter = .linear
        samplerDesc.sAddressMode = .clampToZero
        samplerDesc.tAddressMode = .clampToZero
        guard let sampler = device.makeSamplerState(descriptor: samplerDesc) else { return nil }

        self.device = device
        self.queue = queue
        self.sampler = sampler
        self.textures = TextureCache(device: device)
    }

    /// Encodes one quad per item. `viewport` is in points, `scale` is pixels per point.
    func encode(_ items: [DrawItem], viewport: CGSize, scale: CGFloat, encoder: MTLRenderCommandEncoder) {
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentSamplerState(sampler, index: 0)

        for item in items where item.opacity > 0.001 && !item.text.isEmpty {
            guard let tex = textures.texture(for: item.text, font: item.font, scale: scale) else { continue }

            // Snap the quad's corner to a whole pixel so text stays crisp. `item.scale` grows or
            // shrinks the quad about its center; the texture is not re-rasterized.
            let k = CGFloat(max(0.01, item.scale))
            let size = CGSize(width: CGFloat(tex.pixelSize.x) * k, height: CGFloat(tex.pixelSize.y) * k)
            let origin = CGPoint(x: (item.center.x * scale - size.width / 2).rounded(),
                                 y: (item.center.y * scale - size.height / 2).rounded())

            var u = Uniforms(
                viewport: SIMD2(Float(viewport.width * scale), Float(viewport.height * scale)),
                center: SIMD2(Float(origin.x + size.width / 2), Float(origin.y + size.height / 2)),
                quadSize: SIMD2(Float(size.width), Float(size.height)),
                textRange: tex.textRange,
                base: item.baseColor.simd, highlight: item.highlightColor.simd, glowColor: item.glowColor.simd,
                progress: item.progress, glow: item.glow, opacity: item.opacity,
                glowRadius: Float(item.font.size * 0.1 * Double(scale)),
                texel: SIMD2(1 / tex.pixelSize.x, 1 / tex.pixelSize.y),
                shadow: item.shadow,
                blur: min(1, max(0, item.blur)))
            encoder.setVertexBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 0)
            encoder.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 0)
            encoder.setFragmentTexture(tex.texture, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
    }

    /// Draws the edge glow as four non-overlapping strips (top, bottom, left, right) just wide
    /// enough to hold the falloff, so the GPU never shades the empty middle of the screen.
    func encodeLights(_ lights: LightParams, viewport: CGSize, scale: CGFloat, encoder: MTLRenderCommandEncoder) {
        guard lights.intensity > 0.002 else { return }
        encoder.setRenderPipelineState(rimPipeline)

        let w = Float(viewport.width * scale), h = Float(viewport.height * scale)
        let thickness = Float(lights.thickness * scale)
        // exp(-5) is under 1%: nothing visible lies beyond five falloff lengths.
        let band = min((thickness * 5).rounded(.up), min(w, h) / 2)
        let strips: [(origin: SIMD2<Float>, size: SIMD2<Float>)] = band * 2 >= min(w, h)
            ? [(SIMD2(0, 0), SIMD2(w, h))]
            : [(SIMD2(0, 0), SIMD2(w, band)),                       // top
               (SIMD2(0, h - band), SIMD2(w, band)),                // bottom
               (SIMD2(0, band), SIMD2(band, h - 2 * band)),         // left
               (SIMD2(w - band, band), SIMD2(band, h - 2 * band))]  // right

        for strip in strips {
            var u = RimUniforms(
                viewport: SIMD2(w, h), rectOrigin: strip.origin, rectSize: strip.size,
                thickness: thickness, radius: Float(lights.cornerRadius * scale),
                primary: lights.primary.simd, secondary: lights.secondary.simd,
                intensity: lights.intensity, phase: Float(lights.phase))
            encoder.setVertexBytes(&u, length: MemoryLayout<RimUniforms>.stride, index: 0)
            encoder.setFragmentBytes(&u, length: MemoryLayout<RimUniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
    }

    /// Draws the edge glow hugging `region` (the picture area inside letterbox bars) instead of the whole
    /// view, by pointing the GPU viewport at that rectangle. The shaders are unchanged: to them the region
    /// simply is the screen. The viewport is put back to the whole view afterwards.
    func encodeLights(_ lights: LightParams, in region: CGRect, of viewport: CGSize, scale: CGFloat,
                      encoder: MTLRenderCommandEncoder) {
        encoder.setViewport(MTLViewport(originX: Double((region.minX * scale).rounded()), originY: Double((region.minY * scale).rounded()),
                                        width: Double((region.width * scale).rounded()), height: Double((region.height * scale).rounded()),
                                        znear: 0, zfar: 1))
        encodeLights(lights, viewport: region.size, scale: scale, encoder: encoder)
        encoder.setViewport(MTLViewport(originX: 0, originY: 0, width: Double(viewport.width * scale), height: Double(viewport.height * scale),
                                        znear: 0, zfar: 1))
    }

    /// The passes `encodeCinema` would draw for this frame. A frame that asks for nothing draws nothing.
    static func cinemaPasses(for frame: CinemaFrame) -> [CinemaPass] {
        var passes: [CinemaPass] = []
        if frame.flare > 0.002 { passes.append(.flare) }
        if frame.vignette > 0.002 { passes.append(.vignette) }
        if frame.grain > 0.002 { passes.append(.grain) }
        if frame.barFraction > 0.0001 { passes.append(.bars) }
        return passes
    }

    /// A rounded translucent rectangle, used as the backdrop behind corner-mode lyrics.
    /// `viewport` is in points, `scale` is pixels per point.
    func encodePanel(_ panel: PanelParams, viewport: CGSize, scale: CGFloat, encoder: MTLRenderCommandEncoder) {
        guard panel.color.a > 0.001, panel.rect.width > 0, panel.rect.height > 0 else { return }
        let s = Float(scale)
        var u = PanelUniforms(
            viewport: SIMD2(Float(viewport.width) * s, Float(viewport.height) * s),
            center: SIMD2(Float(panel.rect.midX) * s, Float(panel.rect.midY) * s),
            halfSize: SIMD2(Float(panel.rect.width) * s / 2, Float(panel.rect.height) * s / 2),
            radius: Float(panel.cornerRadius) * s,
            edge: max(1, s),
            color: panel.color.simd)
        encoder.setRenderPipelineState(panelPipeline)
        encoder.setVertexBytes(&u, length: MemoryLayout<PanelUniforms>.stride, index: 0)
        encoder.setFragmentBytes(&u, length: MemoryLayout<PanelUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }

    /// Film-look finishing over everything drawn so far: the flare (additive), the vignette, the grain,
    /// then opaque letterbox bars on top. `viewport` is in points, `scale` is pixels per point.
    func encodeCinema(_ frame: CinemaFrame, viewport: CGSize, scale: CGFloat, encoder: MTLRenderCommandEncoder) {
        let passes = Self.cinemaPasses(for: frame)
        guard !passes.isEmpty else { return }

        let w = Float(viewport.width * scale), h = Float(viewport.height * scale)
        let barPx = Float((frame.barFraction * Double(h)).rounded())
        let picOrigin = SIMD2<Float>(0, barPx), picSize = SIMD2<Float>(w, max(0, h - 2 * barPx))

        func uniforms(origin: SIMD2<Float>, size: SIMD2<Float>) -> CinemaUniforms {
            CinemaUniforms(
                viewport: SIMD2(w, h), rectOrigin: origin, rectSize: size,
                pictureOrigin: picOrigin, pictureSize: picSize,
                flareCenter: SIMD2(Float(frame.flareCenter.x * scale), Float(frame.flareCenter.y * scale)),
                flareHalfWidth: Float(frame.flareHalfWidth * Double(scale)), flare: frame.flare,
                vignette: frame.vignette, grain: frame.grain, seed: frame.grainSeed,
                cell: max(1, Float(scale)), scale: Float(scale))
        }
        func draw(_ pipeline: MTLRenderPipelineState, origin: SIMD2<Float>, size: SIMD2<Float>) {
            guard size.x > 0, size.y > 0 else { return }
            var u = uniforms(origin: origin, size: size)
            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBytes(&u, length: MemoryLayout<CinemaUniforms>.stride, index: 0)
            encoder.setFragmentBytes(&u, length: MemoryLayout<CinemaUniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }

        for pass in passes {
            switch pass {
            case .flare:
                // Only the band around the streak is shaded, not the whole picture.
                let halfW = Float(frame.flareHalfWidth * Double(scale))
                let halfH = Float(48 * scale)   // the halo is gone by about 36 points
                let cx = Float(frame.flareCenter.x * scale), cy = Float(frame.flareCenter.y * scale)
                let x0 = max(picOrigin.x, cx - halfW), x1 = min(picOrigin.x + picSize.x, cx + halfW)
                let y0 = max(picOrigin.y, cy - halfH), y1 = min(picOrigin.y + picSize.y, cy + halfH)
                draw(flarePipeline, origin: SIMD2(x0, y0), size: SIMD2(max(0, x1 - x0), max(0, y1 - y0)))
            case .vignette:
                draw(vignettePipeline, origin: picOrigin, size: picSize)
            case .grain:
                draw(grainPipeline, origin: picOrigin, size: picSize)
            case .bars:
                draw(barPipeline, origin: SIMD2(0, 0), size: SIMD2(w, barPx))
                draw(barPipeline, origin: SIMD2(0, h - barPx), size: SIMD2(w, barPx))
            }
        }
    }

    /// Renders to an offscreen texture and reads it back. Transparent where nothing is drawn.
    public func renderOffscreen(_ items: [DrawItem], lights: LightParams? = nil, cinema: CinemaFrame? = nil,
                                panel: PanelParams? = nil, size: CGSize, scale: CGFloat = 2) -> CGImage? {
        let w = Int(size.width * scale), h = Int(size.height * scale)
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Self.pixelFormat, width: w, height: h, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .shared   // Apple silicon: CPU-readable without a blit.
        guard let target = device.makeTexture(descriptor: desc),
              let cmd = queue.makeCommandBuffer() else { return nil }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        if let lights {
            // With letterbox bars the border hugs the picture, not the full view.
            if let cinema, cinema.barFraction > 0 {
                encodeLights(lights, in: cinema.pictureRect(in: size), of: size, scale: scale, encoder: enc)
            } else {
                encodeLights(lights, viewport: size, scale: scale, encoder: enc)
            }
        }
        if let panel { encodePanel(panel, viewport: size, scale: scale, encoder: enc) }
        encode(items, viewport: size, scale: scale, encoder: enc)
        if let cinema { encodeCinema(cinema, viewport: size, scale: scale, encoder: enc) }
        enc.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()

        var data = Data(count: w * h * 4)
        data.withUnsafeMutableBytes { buf in
            target.getBytes(buf.baseAddress!, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        }
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(
            width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

extension RGBA {
    var simd: SIMD4<Float> { SIMD4(r, g, b, a) }
}
