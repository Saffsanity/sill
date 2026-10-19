import Foundation
import CoreGraphics

let bounds = CGRect(x: 0, y: 0, width: 1000, height: 1000)
let wide = CGSize(width: 1920, height: 1080)
func expect(_ condition: Bool, _ message: String) {
    guard condition else { fatalError(message) }
    print("ok \(message)")
}
let center = VisionInputGeometry.normalized(CGPoint(x: 500, y: 500), bounds: bounds, videoSize: wide)
expect(center == CGPoint(x: 0.5, y: 0.5), "center maps to video center")
expect(VisionInputGeometry.normalized(CGPoint(x: 500, y: 100), bounds: bounds, videoSize: wide) == nil, "top letterbox rejects input")
expect(VisionInputGeometry.normalized(CGPoint(x: 500, y: 900), bounds: bounds, videoSize: wide) == nil, "bottom letterbox rejects input")
expect(VisionInputGeometry.normalized(.zero, bounds: bounds, videoSize: .zero) == nil, "no frame rejects input")
expect(VisionInputGeometry.normalized(.zero, bounds: .zero, videoSize: wide) == nil, "zero view rejects input")
let portrait = CGSize(width: 1080, height: 1920)
expect(VisionInputGeometry.normalized(CGPoint(x: 100, y: 500), bounds: bounds, videoSize: portrait) == nil, "side letterbox rejects input")
let offset = CGRect(x: 50, y: 100, width: 800, height: 600)
expect(VisionInputGeometry.normalized(CGPoint(x: 450, y: 400), bounds: offset, videoSize: wide) == CGPoint(x: 0.5, y: 0.5), "offset bounds normalize correctly")
let quarter = VisionInputGeometry.normalized(CGPoint(x: 250, y: 359.375), bounds: bounds, videoSize: wide)
expect(quarter.map { abs($0.x - 0.25) < 0.000001 && abs($0.y - 0.25) < 0.000001 } == true, "quarter location respects letterbox offset")
