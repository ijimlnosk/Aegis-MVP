import ApplicationServices
import Foundation

/// Accessibility attribute reads and focus helpers for KakaoTalk windows.
enum KakaoAccessibility {
  static func mainWindow(in application: AXUIElement) -> AXUIElement? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value) == .success,
          let windows = value as? [AXUIElement] else { return nil }
    return windows.max { (frame(of: $0)?.size.width ?? 0) * (frame(of: $0)?.size.height ?? 0)
      < (frame(of: $1)?.size.width ?? 0) * (frame(of: $1)?.size.height ?? 0) }
  }

  static func frame(of element: AXUIElement) -> CGRect? {
    var positionValue: CFTypeRef?
    var sizeValue: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
          AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
          positionValue != nil, sizeValue != nil else { return nil }
    let position = positionValue! as! AXValue
    let size = sizeValue! as! AXValue
    var origin = CGPoint.zero
    var dimensions = CGSize.zero
    guard AXValueGetValue(position, .cgPoint, &origin), AXValueGetValue(size, .cgSize, &dimensions) else { return nil }
    return CGRect(origin: origin, size: dimensions)
  }

  static func activate(_ element: AXUIElement) -> Bool {
    if AXUIElementPerformAction(element, kAXPressAction as CFString) == .success { return true }
    guard let frame = frame(of: element) else { return false }
    return KakaoInput.click(at: CGPoint(x: frame.midX, y: frame.midY))
  }

  static func focusedWindow(of application: AXUIElement) -> AXUIElement? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &value) == .success else { return nil }
    return value as! AXUIElement?
  }

  static func focusedTextContains(_ expected: String, in application: AXUIElement) -> Bool {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute as CFString, &value) == .success,
          let element = value as! AXUIElement? else { return false }
    return normalized(text(of: element)).contains(normalized(expected))
  }

  static func focus(_ element: AXUIElement) -> Bool {
    if AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success { return true }
    return activate(element)
  }

  static func role(of element: AXUIElement) -> String {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) == .success else { return "" }
    return value as? String ?? ""
  }

  static func text(of element: AXUIElement) -> String {
    [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute, kAXPlaceholderValueAttribute]
      .compactMap { attribute -> String? in
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
      }
      .joined(separator: " ")
  }

  static func normalized(_ text: String) -> String {
    text.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
  }
}
