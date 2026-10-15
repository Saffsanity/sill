// TEST ONLY: the actual ClipboardSync with a named pasteboard and an in-memory session.
import AppKit
import Combine
import Foundation

let testBoard = NSPasteboard(name: NSPasteboard.Name("me.saffer.sill.test.clipboard-merge.viewer.\(getpid())"))
let defaultsName = "me.saffer.sill.test.clipboard-merge.viewer.\(getpid())"
let testDefaults = UserDefaults(suiteName: defaultsName)!
defer { testDefaults.removePersistentDomain(forName: defaultsName) }

final class StreamClient: ObservableObject {
    var connected = false
    @Published var hostClipboard: Int?
    var onClipboard: ((Clipboard) -> Void)?
    var onMoved: (() -> Void)?
    var sent: [Clipboard] = []
    // Deliberately no gating here: the viewer must obey the host's capability itself.
    func sendClipboard(_ clip: Clipboard) { sent.append(clip) }
}
var checks = 0
func check(_ ok: Bool, _ what: String) {
    checks += 1
    guard ok else { print("FAIL \(what)"); exit(1) }
}
func tick() { RunLoop.main.run(until: Date().addingTimeInterval(0.35)) }
func text(_ text: String) {
    testBoard.prepareForNewContents(with: .currentHostOnly)
    testBoard.setString(text, forType: .string)
}
func image() -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 8, bitsPerPixel: 32)!
    rep.bitmapData!.initialize(repeating: 128, count: 16)
    return rep.representation(using: .png, properties: [:])!
}
func copyImage() {
    testBoard.prepareForNewContents(with: .currentHostOnly)
    testBoard.setData(image(), forType: .png)
}
ClipboardSync.enabled = true
let client = StreamClient()
let sync = ClipboardSync(client: client)
text("before connecting")
tick()
check(client.sent.isEmpty, "disconnected viewer sends nothing")
client.connected = true
tick()
check(client.sent.isEmpty, "older host gets no subscription or existing clipboard")
client.hostClipboard = 1
tick()
check(client.sent == [Clipboard(accepts: 2)], "text host gets the viewer’s accepts 2 subscription")
text("viewer text")
tick()
check(client.sent.last == Clipboard(text: "viewer text"), "viewer text reaches a generation 1 host")
var count = client.sent.count
copyImage()
tick()
check(client.sent.count == count, "generation 1 host gets no image")
client.hostClipboard = 2
tick()
check(client.sent.count == count, "image capability upgrade keeps the existing accepts 2 subscription")
count = client.sent.count
copyImage()
tick()
check(client.sent.count == count + 1 && client.sent.last?.image == image(), "viewer image reaches a generation 2 host")
check(client.sent.last?.payload(within: ClipboardPolicy.maxPayload) != nil, "viewer image fits the device cap")
ClipboardSync.enabled = false
tick()
check(client.sent.last == Clipboard(stop: true), "turning sharing off sends stop")
count = client.sent.count
text("while off")
client.onClipboard?(Clipboard(text: "ignored remote text"))
tick()
check(client.sent.count == count && testBoard.string(forType: .string) == "while off", "off neither sends nor receives")
ClipboardSync.enabled = true
tick()
check(client.sent.count == count + 1 && client.sent.last == Clipboard(accepts: 2), "turning sharing on subscribes without sending the existing clipboard")
count = client.sent.count
client.onClipboard?(Clipboard(text: "remote text", image: image()))
tick()
check(testBoard.string(forType: .string) == "remote text" && testBoard.data(forType: .png) == image(), "remote text and image reach the viewer pasteboard")
check(client.sent.count == count, "received copy is never echoed")
client.hostClipboard = nil
client.hostClipboard = 2
tick()
check(client.sent.count == count + 1 && client.sent.last == Clipboard(accepts: 2), "quick reconnect with the same generation subscribes again")
count = client.sent.count
client.onMoved?()
tick()
check(client.sent.count == count + 1 && client.sent.last == Clipboard(accepts: 2), "a moved connection subscribes again")
client.hostClipboard = nil
tick()
count = client.sent.count
text("disabled host")
tick()
check(client.sent.count == count, "disabled host gets no clipboard traffic")
print("Viewer checks: \(checks) passed")
