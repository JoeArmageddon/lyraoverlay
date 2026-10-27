import Foundation

/// Compiled at runtime: SwiftPM doesn't build .metal files, and one small shader
/// pair doesn't justify an Xcode project yet.
enum Shaders {
    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    // Must match `Uniforms` in MetalRenderer.swift field for field.
    struct Uniforms {
        float2 viewport;     // pixels
        float2 center;       // pixels, y down
        float2 quadSize;     // pixels
        float2 textRange;    // u of the text's left and right edge
        float4 base;
        float4 highlight;
        float4 glowColor;
        float progress;
        float glow;
        float opacity;
        float glowRadius;    // pixels
        float2 texel;        // 1 / texture size
        float shadow;
        float blur;          // 0 sharp ... 1 fully defocused
    };

    struct VOut {
        float4 position [[position]];
        float2 uv;
    };

    vertex VOut lyric_vertex(uint vid [[vertex_id]], constant Uniforms& u [[buffer(0)]]) {
        const float2 corners[4] = { float2(0, 0), float2(1, 0), float2(0, 1), float2(1, 1) };
        float2 c = corners[vid];
        float2 px = u.center + (c - 0.5) * u.quadSize;
        VOut o;
        o.position = float4(px.x / u.viewport.x * 2.0 - 1.0, 1.0 - px.y / u.viewport.y * 2.0, 0.0, 1.0);
        o.uv = c;
        return o;
    }

    // Average alpha on two rings around the pixel: a cheap blur for glow and shadow.
    static float blurredAlpha(texture2d<float> tex, sampler s, float2 uv, float2 step) {
        const float2 dirs[8] = {
            float2(1, 0), float2(0.7071, 0.7071), float2(0, 1), float2(-0.7071, 0.7071),
            float2(-1, 0), float2(-0.7071, -0.7071), float2(0, -1), float2(0.7071, -0.7071)
        };
        float sum = tex.sample(s, uv).a * 2.0;
        for (int i = 0; i < 8; i++) {
            sum += tex.sample(s, uv + dirs[i] * step * 0.5).a;
            sum += tex.sample(s, uv + dirs[i] * step).a;
        }
        return sum / 18.0;
    }

    // Three rings of eight taps: wider and smoother than `blurredAlpha`, for defocusing the glyphs
    // themselves. Used only while an animation is blurring the text.
    static float defocusedAlpha(texture2d<float> tex, sampler s, float2 uv, float2 step) {
        const float2 dirs[8] = {
            float2(1, 0), float2(0.7071, 0.7071), float2(0, 1), float2(-0.7071, 0.7071),
            float2(-1, 0), float2(-0.7071, -0.7071), float2(0, -1), float2(0.7071, -0.7071)
        };
        float sum = tex.sample(s, uv).a * 3.0;
        for (int i = 0; i < 8; i++) {
            sum += tex.sample(s, uv + dirs[i] * step * 0.33).a * 1.5;
            sum += tex.sample(s, uv + dirs[i] * step * 0.66).a;
            sum += tex.sample(s, uv + dirs[i] * step).a * 0.6;
        }
        return sum / (3.0 + 8.0 * (1.5 + 1.0 + 0.6));
    }

    fragment float4 lyric_fragment(VOut in [[stage_in]],
                                   constant Uniforms& u [[buffer(0)]],
                                   texture2d<float> tex [[texture(0)]],
                                   sampler s [[sampler(0)]]) {
        float a = tex.sample(s, in.uv).a;
        // Defocus: trade the sharp glyph alpha for a wide blur of it. Skipped entirely at blur 0,
        // so unblurred text takes exactly the path it always did.
        if (u.blur > 0.0) {
            float radius = u.blur * 1.2 * u.glowRadius;   // about 0.12 * font size, in pixels
            a = mix(a, defocusedAlpha(tex, s, in.uv, radius * u.texel), u.blur);
        }

        // Where the sung/unsung edge is, in text space 0...1, with a soft edge.
        float x = (in.uv.x - u.textRange.x) / max(u.textRange.y - u.textRange.x, 1e-4);
        const float soft = 0.05;
        float edge = mix(-soft, 1.0 + soft, u.progress);
        float sung = 1.0 - smoothstep(edge - soft, edge + soft, x);

        float4 color = mix(u.base, u.highlight, sung);
        float4 outc = float4(color.rgb * color.a * a, color.a * a);

        float2 step = u.glowRadius * u.texel;

        // Dark halo first, then colored glow over it, both behind the glyphs.
        // The halo is much tighter than the glow: a wide one smears thin, translucent text.
        if (u.shadow > 0.0) {
            // A crisp dark outline around defocused text would look wrong, so it fades with the blur.
            float sa = clamp(blurredAlpha(tex, s, in.uv, step * 0.35) * 1.2 * u.shadow, 0.0, 1.0);
            if (u.blur > 0.0) { sa *= 1.0 - u.blur; }
            outc = outc + float4(0.0, 0.0, 0.0, sa) * (1.0 - outc.a);
        }
        if (u.glow > 0.0) {
            float blur = blurredAlpha(tex, s, in.uv, step);
            // The glow follows the sung part only, with a wider soft edge.
            float glowSung = 1.0 - smoothstep(edge - 0.15, edge + 0.15, x);
            float ga = clamp(blur * 1.8 * u.glow * glowSung * u.highlight.a, 0.0, 1.0);
            if (u.blur > 0.0) { ga *= mix(1.0, 0.4, u.blur); }   // the glow is already soft: let it follow the text
            outc = outc + float4(u.glowColor.rgb * ga, ga) * (1.0 - outc.a);
        }
        return outc * u.opacity;
    }

    // ---- Edge lighting -------------------------------------------------------------

    // Must match `RimUniforms` in MetalRenderer.swift field for field.
    struct RimUniforms {
        float2 viewport;     // pixels
        float2 rectOrigin;   // the strip being drawn, pixels, y down
        float2 rectSize;
        float thickness;     // falloff distance, pixels
        float radius;        // display corner radius, pixels
        float4 primary;
        float4 secondary;
        float intensity;
        float phase;         // gradient rotation in turns
    };

    struct RimOut {
        float4 position [[position]];
        float2 px;
    };

    vertex RimOut rim_vertex(uint vid [[vertex_id]], constant RimUniforms& u [[buffer(0)]]) {
        const float2 corners[4] = { float2(0, 0), float2(1, 0), float2(0, 1), float2(1, 1) };
        float2 px = u.rectOrigin + corners[vid] * u.rectSize;
        RimOut o;
        o.position = float4(px.x / u.viewport.x * 2.0 - 1.0, 1.0 - px.y / u.viewport.y * 2.0, 0.0, 1.0);
        o.px = px;
        return o;
    }

    fragment float4 rim_fragment(RimOut in [[stage_in]], constant RimUniforms& u [[buffer(0)]]) {
        float2 p = in.px;
        float2 halfSize = u.viewport * 0.5;

        // Signed distance to the rounded screen rectangle; d is how far inside the edge we are.
        float2 q = abs(p - halfSize) - (halfSize - u.radius);
        float outside = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - u.radius;
        float d = max(-outside, 0.0);

        // A wide soft falloff plus a tighter bright core hugging the edge.
        float glow = exp(-d / u.thickness) * 0.75 + exp(-d / (u.thickness * 0.2)) * 0.55;

        // Colors blend around the screen like a wheel, rotating with `phase`.
        float2 v = p - halfSize;
        float turn = atan2(v.y, v.x) * 0.15915494 + 0.5 + u.phase;
        float wave = 0.5 + 0.5 * cos(6.2831853 * turn);
        float t = smoothstep(0.3, 0.9, wave);   // favors the primary color
        float3 color = mix(u.primary.rgb, u.secondary.rgb, t);

        // Dither by about one 8-bit step so the long falloff doesn't band.
        float noise = fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453) - 0.5;
        float a = clamp(glow * u.intensity + noise * (1.0 / 255.0), 0.0, 1.0);
        return float4(color * a, a);
    }

    // ---- Cinema finishing ----------------------------------------------------------

    // Must match `CinemaUniforms` in MetalRenderer.swift field for field.
    struct CinemaUniforms {
        float2 viewport;       // pixels
        float2 rectOrigin;     // the quad being drawn, pixels, y down
        float2 rectSize;
        float2 pictureOrigin;  // the picture area inside the bars, pixels
        float2 pictureSize;
        float2 flareCenter;    // pixels
        float flareHalfWidth;  // pixels
        float flare;
        float vignette;
        float grain;
        float seed;
        float cell;            // grain cell size in pixels (one point)
        float scale;           // pixels per point
        float pad;
    };

    struct CinemaOut {
        float4 position [[position]];
        float2 px;
    };

    vertex CinemaOut cinema_vertex(uint vid [[vertex_id]], constant CinemaUniforms& u [[buffer(0)]]) {
        const float2 corners[4] = { float2(0, 0), float2(1, 0), float2(0, 1), float2(1, 1) };
        float2 px = u.rectOrigin + corners[vid] * u.rectSize;
        CinemaOut o;
        o.position = float4(px.x / u.viewport.x * 2.0 - 1.0, 1.0 - px.y / u.viewport.y * 2.0, 0.0, 1.0);
        o.px = px;
        return o;
    }

    // Integer hash (PCG style): good white noise from pixel coordinates, no visible patterns.
    static uint pcg(uint v) {
        uint state = v * 747796405u + 2891336453u;
        uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
        return (word >> 22u) ^ word;
    }

    static float hash01(uint2 p, uint seed) {
        return float(pcg(p.x + pcg(p.y + pcg(seed)))) * (1.0 / 4294967295.0);
    }

    // Anamorphic streak: a thin bright core with soft tails, blue-white, added to what is there.
    fragment float4 flare_fragment(CinemaOut in [[stage_in]], constant CinemaUniforms& u [[buffer(0)]]) {
        float dx = (in.px.x - u.flareCenter.x) / max(u.flareHalfWidth, 1.0);
        float dy = (in.px.y - u.flareCenter.y) / u.scale;     // points
        float along = pow(max(0.0, 1.0 - abs(dx)), 2.2);       // long soft tails, gone at the ends
        float core = exp(-(dy * dy) / (2.0 * 1.1 * 1.1));      // about 2 points thick
        float halo = 0.22 * exp(-(dy * dy) / (2.0 * 12.0 * 12.0));
        float hot = exp(-(dx * dx) / 0.004) * exp(-(dy * dy) / (2.0 * 5.0 * 5.0)) * 0.5;   // a small bloom at the heart
        float s = clamp((core + halo) * along * 0.85 + hot, 0.0, 1.0) * u.flare;
        float3 color = float3(0.72, 0.86, 1.0);
        return float4(color * s, s);
    }

    // Darkens toward the corners of the picture, smoothly, with no visible ring.
    fragment float4 vignette_fragment(CinemaOut in [[stage_in]], constant CinemaUniforms& u [[buffer(0)]]) {
        float2 c = u.pictureOrigin + u.pictureSize * 0.5;
        float2 n = (in.px - c) / (u.pictureSize * 0.5);        // -1...1 across the picture
        float r = length(n) * 0.70710678;                      // 0 at the centre, 1 in the corners
        float v = smoothstep(0.30, 1.05, r);
        float a = clamp(u.vignette * 0.9 * v * v, 0.0, 1.0);
        // Dither by one 8-bit step so the gradient doesn't band.
        float noise = hash01(uint2(in.px), 7u) - 0.5;
        a = clamp(a + noise * (1.0 / 255.0) * step(0.001, u.vignette), 0.0, 1.0);
        return float4(0.0, 0.0, 0.0, a);
    }

    // Film grain: fine, both lightening and darkening, a new pattern each film frame.
    fragment float4 grain_fragment(CinemaOut in [[stage_in]], constant CinemaUniforms& u [[buffer(0)]]) {
        uint2 cell = uint2(max(float2(0.0), in.px) / max(u.cell, 1.0));
        uint seed = uint(u.seed);
        // Two uniform samples summed give a bell-shaped distribution: mostly subtle, few harsh specks.
        float n = hash01(cell, seed) + hash01(cell + uint2(7919u, 104729u), seed) - 1.0;   // -1...1
        float a = clamp(abs(n) * u.grain * 0.32, 0.0, 1.0);
        return n > 0.0 ? float4(a, a, a, a) : float4(0.0, 0.0, 0.0, a);
    }

    // Opaque black bars.
    fragment float4 bar_fragment(CinemaOut in [[stage_in]], constant CinemaUniforms& u [[buffer(0)]]) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    // ---- Backdrop panel (corner mode) ------------------------------------------------

    // Must match `PanelUniforms` in MetalRenderer.swift field for field.
    struct PanelUniforms {
        float2 viewport;     // pixels
        float2 center;       // pixels, y down
        float2 halfSize;     // pixels, half the panel's width and height
        float radius;        // pixels
        float edge;          // pixels of antialiasing and highlight rim
        float4 color;        // straight (not premultiplied) fill color
    };

    struct PanelOut {
        float4 position [[position]];
        float2 px;
    };

    vertex PanelOut panel_vertex(uint vid [[vertex_id]], constant PanelUniforms& u [[buffer(0)]]) {
        const float2 corners[4] = { float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, 1) };
        // One pixel of slack on every side so the antialiased edge isn't clipped.
        float2 px = u.center + corners[vid] * (u.halfSize + 2.0);
        PanelOut o;
        o.position = float4(px.x / u.viewport.x * 2.0 - 1.0, 1.0 - px.y / u.viewport.y * 2.0, 0.0, 1.0);
        o.px = px;
        return o;
    }

    fragment float4 panel_fragment(PanelOut in [[stage_in]], constant PanelUniforms& u [[buffer(0)]]) {
        // Signed distance to the rounded rectangle: negative inside.
        float2 q = abs(in.px - u.center) - (u.halfSize - u.radius);
        float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - u.radius;

        float coverage = clamp(0.5 - d / u.edge, 0.0, 1.0);          // antialiased shape
        float rim = smoothstep(-2.5 * u.edge, 0.0, d) * coverage;     // brighter hairline just inside the edge
        float3 rgb = mix(u.color.rgb, float3(1.0), rim * 0.22);
        float a = u.color.a * coverage;
        return float4(rgb * a, a);
    }
    """
}
