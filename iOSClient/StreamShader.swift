import Foundation

/// The Metal shader MetalStreamRenderer draws a picture with, compiled when it starts (no .metal file
/// to build). One pass resamples along one axis with one of PictureSmoothing's filters, exactly as
/// `PictureSmoothing.resample` does (a check holds it to that on the GPU): across into an
/// intermediate texture, then down into the drawable. Pure text and the parameters' layout.
enum StreamShader {
    static let vertex = "streamVertex"
    static let fragment = "streamPass"

    /// The fragment's parameters, laid out as the shader's `Params` (32 bytes on both sides).
    struct Params {
        /// Where the pass draws in its target, in pixels (the picture's rectangle in the drawable).
        var origin: SIMD2<Float>
        var size: SIMD2<Float>
        /// PictureSmoothing.Filter.shaderMode.
        var filter: Int32
        /// 0 across, 1 down.
        var axis: Int32
        /// Non-zero on the last pass: Lanczos and bicubic ring past black and white.
        var clampOut: Int32
    }

    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct Params { float2 origin; float2 size; int filter; int axis; int clampOut; };
    struct VOut { float4 position [[position]]; };

    // A triangle that covers the viewport: the picture's rectangle.
    vertex VOut streamVertex(uint vid [[vertex_id]]) {
        float2 p = float2((vid << 1) & 2, vid & 2);
        VOut o;
        o.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
        return o;
    }

    static float reach(int f) { return f == 1 ? 1.0 : (f == 2 ? 2.0 : 3.0); }

    // Tent (bilinear), Catmull-Rom (bicubic), Lanczos-3: PictureSmoothing.kernel.
    static float weight(int f, float x) {
        x = fabs(x);
        if (f == 1) { return max(0.0, 1.0 - x); }
        if (f == 2) {
            if (x < 1.0) { return 1.5 * x * x * x - 2.5 * x * x + 1.0; }
            if (x < 2.0) { return -0.5 * x * x * x + 2.5 * x * x - 4.0 * x + 2.0; }
            return 0.0;
        }
        if (x >= 3.0) { return 0.0; }
        if (x < 1e-6) { return 1.0; }
        float px = M_PI_F * x;
        return 3.0 * sin(px) * sin(px / 3.0) / (px * px);
    }

    fragment float4 streamPass(VOut in [[stage_in]], texture2d<float, access::read> src [[texture(0)]],
                               constant Params& p [[buffer(0)]]) {
        float2 local = in.position.xy - p.origin;            // this output pixel's centre: i + 0.5
        bool across = p.axis == 0;
        int m = across ? int(src.get_width()) : int(src.get_height());
        int otherLast = across ? int(src.get_height()) - 1 : int(src.get_width()) - 1;
        float scale = (across ? p.size.x : p.size.y) / float(m);
        float along = across ? local.x : local.y;
        int other = clamp(int(across ? local.y : local.x), 0, otherLast);
        float4 out;
        if (p.filter == 0) {
            int k = min(m - 1, int(along / scale));
            out = src.read(across ? uint2(k, other) : uint2(other, k));
        } else {
            float c = along / scale - 0.5;
            float s = min(scale, 1.0);
            float r = reach(p.filter) / s;
            float4 acc = float4(0.0);
            float sum = 0.0;
            for (int k = int(floor(c - r)) + 1; float(k) <= c + r; k++) {
                float w = weight(p.filter, (float(k) - c) * s);
                int kk = clamp(k, 0, m - 1);
                acc += src.read(across ? uint2(kk, other) : uint2(other, kk)) * w;
                sum += w;
            }
            int near = clamp(int(round(c)), 0, m - 1);
            out = sum == 0.0 ? src.read(across ? uint2(near, other) : uint2(other, near)) : acc / sum;
        }
        return p.clampOut != 0 ? clamp(out, 0.0, 1.0) : out;
    }
    """
}
