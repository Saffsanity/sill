import Foundation
var checks = 0
func expect(_ value: @autoclosure () -> Bool, _ label: String) {
    checks += 1
    guard value() else { fatalError("FAIL: \(label)") }
}
expect(VisionTextInput.events("s", modifiers: .command) == KeyChord.press(0x16, with: .command), "Command S is exclusively a balanced HID chord")
expect(VisionTextInput.events("V", modifiers: [.command, .shift]) == KeyChord.press(0x19, with: [.command, .shift]), "Shifted shortcut maps to unshifted HID")
expect(VisionTextInput.events("é", modifiers: .command) == [.text("é")], "Composed character stays Unicode")
expect(VisionTextInput.events("你好 👋", modifiers: []) == [.text("你好 👋")], "IME/dictation commit stays one text event")
expect(VisionTextInput.events("text", modifiers: .control) == [.text("text")], "Batch text cannot become repeated shortcuts")
expect(VisionTextInput.events("A", modifiers: .shift) == [.text("A")], "Shift-only text is already composed")
expect(VisionTextInput.events("\n", modifiers: .command) == KeyChord.press(0x28, with: .command), "Modified Return uses key path")
var cursor = PadCursor()
cursor.adopt(anchor: CGPoint(x: 0.2, y: 0.8), reseeds: 1)
cursor.move(dx: 0.1, dy: -0.2)
expect(abs(cursor.cursor.x - 0.3) < 0.00001 && abs(cursor.cursor.y - 0.6) < 0.00001, "Relative drag begins from remote anchor")
cursor.move(dx: 5, dy: -5)
expect(cursor.cursor == CGPoint(x: 1, y: 0), "Relative movement clamps at picture edges")
cursor.catchUp(anchor: CGPoint(x: 0.5, y: 0.4), reseeds: 1)
expect(cursor.cursor == CGPoint(x: 1, y: 0), "Own feedback does not reseed cursor")
cursor.catchUp(anchor: CGPoint(x: 0.5, y: 0.4), reseeds: 2)
expect(cursor.cursor == CGPoint(x: 0.5, y: 0.4), "Mac pointer takeover reseeds mid-stroke")
for i in 0..<1000 {
    cursor.move(dx: Double(i % 37 - 18) / 29, dy: Double(i % 41 - 20) / 31)
    expect((0...1).contains(cursor.cursor.x) && (0...1).contains(cursor.cursor.y), "Random movement remains bounded")
}
let old = Date(timeIntervalSince1970: 100), next = Date(timeIntervalSince1970: 101)
expect(VisionSessionPolicy.acceptsCompletion(startedAt: old, currentAt: old, connected: true), "Paste resolves on original connected session")
expect(!VisionSessionPolicy.acceptsCompletion(startedAt: old, currentAt: next, connected: true), "Paste cannot target replacement session")
expect(!VisionSessionPolicy.acceptsCompletion(startedAt: old, currentAt: nil, connected: false), "Paste cannot complete disconnected")
expect(!VisionSessionPolicy.acceptsCompletion(startedAt: nil, currentAt: nil, connected: true), "Missing session never authorizes deferred paste")
print("vision-controls: \(checks) checks passed")
