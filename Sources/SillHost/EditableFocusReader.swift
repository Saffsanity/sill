import Foundation
import ApplicationServices
import StreamProtocol

/// Runs only on a detached worker; fixed call count and per-element timeout bound AX IPC.
/// Strict equality deliberately misses apps whose AX hit target is a child of their editor.
/// It never reads value, title, description, selection or document content.
enum EditableFocusReader {
    static func read(point: CGPoint, expectedPID: pid_t?, expectedWindow: CGRect?) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let deadline = Date().addingTimeInterval(0.5)
        func prepare(_ element: AXUIElement) { AXUIElementSetMessagingTimeout(element, 0.05) }
        func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
            guard Date() < deadline else { return nil }
            prepare(element)
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
            return value
        }
        func element(_ value: CFTypeRef?) -> AXUIElement? {
            guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
            return (value as! AXUIElement)
        }
        let system = AXUIElementCreateSystemWide()
        prepare(system)
        guard let app = element(attribute(system, kAXFocusedApplicationAttribute)),
              let focused = element(attribute(app, kAXFocusedUIElementAttribute)) else { return false }
        var pid: pid_t = 0
        guard AXUIElementGetPid(focused, &pid) == .success,
              expectedPID == nil || expectedPID == pid else { return false }
        func hitMatches() -> Bool {
            guard Date() < deadline else { return false }
            var hit: AXUIElement?
            return AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success &&
                hit.map { CFEqual($0, focused) } == true
        }
        guard hitMatches() else { return false }
        let role = attribute(focused, kAXRoleAttribute) as? String
        let enabled = attribute(focused, kAXEnabledAttribute) as? Bool
        var settable = DarwinBoolean(false)
        guard Date() < deadline,
              AXUIElementIsAttributeSettable(focused, kAXValueAttribute as CFString, &settable) == .success else { return false }
        var sourceMatches = expectedWindow == nil
        if let expectedWindow {
            guard let window = element(attribute(focused, kAXWindowAttribute)),
                  let position = attribute(window, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
                  let size = attribute(window, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() else { return false }
            var origin = CGPoint.zero, dimensions = CGSize.zero
            guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
                  AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else { return false }
            let actual = CGRect(origin: origin, size: dimensions)
            sourceMatches = EditableFocusPolicy.sameWindowBounds(actual, expectedWindow)
        }
        guard EditableFocusPolicy.accepts(role: role, enabled: enabled, valueSettable: settable.boolValue,
                                         clickedIsFocused: true, sourceMatches: sourceMatches),
              let stillFocused = element(attribute(app, kAXFocusedUIElementAttribute)),
              CFEqual(stillFocused, focused), hitMatches(), Date() < deadline else { return false }
        return true
    }
}
