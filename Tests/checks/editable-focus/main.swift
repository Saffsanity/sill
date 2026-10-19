import Foundation
import CoreGraphics

func check(_ ok: Bool, _ what: String) { if !ok { fatalError(what) } }
for role in ["AXTextField", "AXTextArea", "AXComboBox"] {
    check(EditableFocusPolicy.accepts(role: role, enabled: true, valueSettable: true, clickedIsFocused: true, sourceMatches: true), "editable role")
    check(!EditableFocusPolicy.accepts(role: role, enabled: true, valueSettable: true, clickedIsFocused: false, sourceMatches: true), "Photos clicked while old editor remains focused")
    check(!EditableFocusPolicy.accepts(role: role, enabled: true, valueSettable: true, clickedIsFocused: true, sourceMatches: false), "other source/window")
    check(!EditableFocusPolicy.accepts(role: role, enabled: true, valueSettable: false, clickedIsFocused: true, sourceMatches: true), "readonly text")
    for enabled: Bool? in [false, nil] {
        check(!EditableFocusPolicy.accepts(role: role, enabled: enabled, valueSettable: true, clickedIsFocused: true, sourceMatches: true), "disabled/unknown")
    }
}
for role: String? in [nil, "AXStaticText", "AXImage", "AXSlider", "AXButton", "AXWebArea", "AXGroup"] {
    check(!EditableFocusPolicy.accepts(role: role, enabled: true, valueSettable: true, clickedIsFocused: true, sourceMatches: true), "noneditor roles even if writable")
}
let bounds = CGRect(x: 10, y: 20, width: 100, height: 200)
check(EditableFocusPolicy.sameWindowBounds(bounds, bounds), "stacked equal bounds must collide")
check(EditableFocusPolicy.sameWindowBounds(bounds, CGRect(x: 11, y: 21, width: 100, height: 200)), "AX geometry tolerance also applies to ambiguity")
check(!EditableFocusPolicy.sameWindowBounds(bounds, CGRect(x: 12, y: 20, width: 100, height: 200)), "distinct windows")
let request = EditableFocus(token: "opaque", source: .desktop, x: 0.3, y: 0.6)
check(request.isValidRequest, "request valid")
check(Wire.decode(EditableFocus.self, from: Wire.encode(request)) == request, "request roundtrip")
var reply = request; reply.editable = false
check(!reply.isValidRequest, "reply cannot initiate read")
check(Wire.decode(EditableFocus.self, from: Wire.encode(reply)) == reply, "reply roundtrip")
for bad in [Double.nan, .infinity, -0.1, 1.1] {
    var r = request; r.x = bad; check(!r.isValidRequest, "invalid coordinates")
}
var empty = request; empty.token = ""; check(!empty.isValidRequest, "empty token")
empty.token = String(repeating: "x", count: 129); check(!empty.isValidRequest, "oversize token")
let legacy = Data(#"{"macName":"old","windows":[],"active":{"desktop":{}}}"#.utf8)
check(Wire.decode(WindowList.self, from: legacy)?.editableFocus == nil, "old host no capability")
let modern = WindowList(macName: "new", windows: [], active: .desktop, editableFocus: 1)
check(Wire.decode(WindowList.self, from: Wire.encode(modern))?.editableFocus == 1, "optional capability")
struct LegacyList: Decodable { var macName: String; var active: StreamSource }
check(Wire.decode(LegacyList.self, from: Wire.encode(modern))?.active == .desktop, "legacy ignores capability")
let framed = StreamMessage(kind: .editableFocus, timestamp: 0, isKeyframe: false, payload: Wire.encode(request)).serialized()
check(StreamMessage.parseHeader(framed)?.kind == .editableFocus && framed[0] == 33, "kind 33 framing")
// Pre-extension readers use exactly rawValue lookup plus unknown fallback for every missing kind.
enum LegacyKind: UInt8 { case frame = 1; case clipboard = 32; case unknown = 255 }
check((LegacyKind(rawValue: framed[0]) ?? .unknown) == .unknown, "legacy skips new kind")
print("editable-focus: policy and wire checks passed")
