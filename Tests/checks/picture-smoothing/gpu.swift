// The stream shader (iOSClient/StreamShader.swift) on this Mac's GPU against PictureSmoothing's CPU
// reference: one pass of every filter, across and down, growing, shrinking and at the same size,
// pixel for pixel. Compiled with StreamShader.swift and PictureSmoothing.swift (run.sh). Without a
// Metal device (some CI machines) it says so and passes.
import Foundation
import Metal

var failures = 0, checks = 0
func check(_ ok: Bool, _ what: String) {
    checks += 1
    if ok { print("ok   \(what)") } else { failures += 1; print("FAIL \(what)") }
}

guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
    print("gpu: no Metal device here: skipped")
    exit(0)
}
let library: MTLLibrary
do { library = try device.makeLibrary(source: StreamShader.source, options: nil) } catch {
    print("FAIL the shader compiles: \(error)"); exit(1)
}
let descriptor = MTLRenderPipelineDescriptor()
descriptor.vertexFunction = library.makeFunction(name: StreamShader.vertex)
descriptor.fragmentFunction = library.makeFunction(name: StreamShader.fragment)
descriptor.colorAttachments[0].pixelFormat = .rgba32Float
let pipeline = try! device.makeRenderPipelineState(descriptor: descriptor)

func texture(_ w: Int, _ h: Int, _ values: [Float]?) -> MTLTexture {
    let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba32Float, width: w, height: h, mipmapped: false)
    d.usage = [.shaderRead, .renderTarget]
    d.storageMode = .shared
    let t = device.makeTexture(descriptor: d)!
    if let values {
        let px: [Float] = values.flatMap { v -> [Float] in [v, v, v, 1] }
        t.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: px, bytesPerRow: w * 16)
    }
    return t
}

/// One pass of the shader over `row` (m pixels) to `n`, across (axis 0) or down (axis 1).
func gpuPass(_ row: [Double], to n: Int, filter: PictureSmoothing.Filter, axis: Int32, clampOut: Bool) -> [Double] {
    let m = row.count
    let values = row.map(Float.init)
    // Two lines of the row, so the other axis has more than one pixel to keep apart.
    let src = axis == 0 ? texture(m, 2, values + values) : texture(2, m, values.flatMap { [$0, $0] })
    let dst = axis == 0 ? texture(n, 2, nil) : texture(2, n, nil)
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = dst
    pass.colorAttachments[0].loadAction = .clear
    pass.colorAttachments[0].storeAction = .store
    let buffer = queue.makeCommandBuffer()!
    let encoder = buffer.makeRenderCommandEncoder(descriptor: pass)!
    encoder.setRenderPipelineState(pipeline)
    var p = StreamShader.Params(origin: SIMD2(0, 0), size: SIMD2(Float(dst.width), Float(dst.height)), filter: filter.shaderMode, axis: axis,
                                clampOut: clampOut ? 1 : 0)
    encoder.setFragmentBytes(&p, length: MemoryLayout<StreamShader.Params>.stride, index: 0)
    encoder.setFragmentTexture(src, index: 0)
    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    encoder.endEncoding()
    buffer.commit()
    buffer.waitUntilCompleted()
    var out = [Float](repeating: 0, count: dst.width * dst.height * 4)
    dst.getBytes(&out, bytesPerRow: dst.width * 16, from: MTLRegionMake2D(0, 0, dst.width, dst.height), mipmapLevel: 0)
    return (0..<n).map { i in Double(axis == 0 ? out[i * 4] : out[i * 2 * 4]) }
}

let stripes = (0..<64).map { ($0 / 4) % 2 == 0 ? 0.0 : 1.0 }
let ramp = (0..<64).map { Double($0) / 63 }
for filter in [PictureSmoothing.Filter.nearest, .bilinear, .bicubic, .lanczos] {
    for (name, row) in [("stripes", stripes), ("a ramp", ramp)] {
        for n in [68, 30, 64, 160] {
            let want = PictureSmoothing.resample(row, to: n, filter: filter)
            for axis: Int32 in [0, 1] {
                let got = gpuPass(row, to: n, filter: filter, axis: axis, clampOut: false)
                let worst = zip(got, want).map { abs($0 - $1) }.max() ?? 1
                check(got.count == want.count && worst < 1e-3,
                      "\(filter), \(name) 64 → \(n) \(axis == 0 ? "across" : "down"): the reference within \(String(format: "%.1e", worst))")
            }
        }
    }
}
let rung = gpuPass(stripes, to: 68, filter: .lanczos, axis: 0, clampOut: true)
check(rung.allSatisfy { $0 >= 0 && $0 <= 1 }, "the last pass clamps Lanczos's ringing to black and white")

print("\(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
