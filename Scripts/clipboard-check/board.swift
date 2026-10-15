// TEST ONLY: a synthetic host's named pasteboard, never the general clipboard.
import AppKit
import Foundation

let args = CommandLine.arguments
guard args.count >= 3, args[1].hasPrefix("me.saffer.sill.test.clipboard-merge.") else { exit(2) }
let board = NSPasteboard(name: NSPasteboard.Name(args[1]))
func image() -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 8, bitsPerPixel: 32)!
    rep.bitmapData!.initialize(repeating: 128, count: 16)
    return rep.representation(using: .png, properties: [:])!
}
if args[2] == "png" {
    print(image().base64EncodedString())
} else if args[2] == "read" {
    let info: [String: Any] = ["text": board.string(forType: .string) ?? "", "image": board.data(forType: .png) != nil,
                               "own": board.types?.contains(NSPasteboard.PasteboardType("me.saffer.sill.clipboard")) == true]
    print(String(decoding: try! JSONSerialization.data(withJSONObject: info, options: .sortedKeys), as: UTF8.self))
} else {
    board.prepareForNewContents(with: .currentHostOnly)
    let item = NSPasteboardItem()
    if args[2] == "text" || args[2] == "both" { item.setString(args.count > 3 ? args[3] : "sample", forType: .string) }
    if ["image", "both", "marked"].contains(args[2]) { item.setData(image(), forType: .png) }
    if args[2] == "marked" { item.setString("1", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")) }
    board.writeObjects([item])
}
