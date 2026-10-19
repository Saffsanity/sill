import Foundation
import CoreGraphics

/// An explicit, one-shot check of the last delivered left click, never a focus subscription.
/// Request: editable nil. Reply to that connection alone: editable true only for the exact
/// clicked, focused editable AX element. Unknown, stale or unsupported is false. No text is read.
public struct EditableFocus: Codable, Hashable {
    public static let generation = 1
    public var token: String
    public var source: StreamSource
    public var x: Double
    public var y: Double
    public var editable: Bool?
    public init(token: String, source: StreamSource, x: Double, y: Double, editable: Bool? = nil) {
        self.token = token; self.source = source; self.x = x; self.y = y; self.editable = editable
    }
    public var isValidRequest: Bool {
        editable == nil && !token.isEmpty && token.utf8.count <= 128 && source != .none &&
        x.isFinite && y.isFinite && (0...1).contains(x) && (0...1).contains(y)
    }
}

/// Conservative evidence policy shared with pure regression checks. A focused old text field
/// alone is insufficient: clicking Photos while that field retains focus must stay false.
public enum EditableFocusPolicy {
    public static func sameWindowBounds(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) < 2 && abs(lhs.origin.y - rhs.origin.y) < 2 &&
        abs(lhs.size.width - rhs.size.width) < 2 && abs(lhs.size.height - rhs.size.height) < 2
    }

    public static func accepts(role: String?, enabled: Bool?, valueSettable: Bool,
                               clickedIsFocused: Bool, sourceMatches: Bool) -> Bool {
        clickedIsFocused && sourceMatches && enabled == true && valueSettable &&
        ["AXTextField", "AXTextArea", "AXComboBox"].contains(role ?? "")
    }
}
