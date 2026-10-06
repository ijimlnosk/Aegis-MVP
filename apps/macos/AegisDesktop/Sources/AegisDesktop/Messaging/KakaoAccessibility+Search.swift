import ApplicationServices
import Foundation

/// Bounded tree searches that locate the chat search result and message input.
extension KakaoAccessibility {
  static func matchingElement(named name: String, in root: AXUIElement) -> AXUIElement? {
    var queue = [root]
    var examined = 0
    var partialMatch: AXUIElement?
    let target = normalized(name)
    while !queue.isEmpty, examined < 500 {
      let element = queue.removeFirst()
      examined += 1
      let candidate = normalized(text(of: element))
      if !isSearchField(element), candidate == target {
        return pressableAncestor(of: element) ?? element
      }
      if !isSearchField(element), partialMatch == nil, candidate.contains(target) {
        partialMatch = pressableAncestor(of: element) ?? element
      }
      var children: CFTypeRef?
      if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
         let values = children as? [AXUIElement] {
        queue.append(contentsOf: values)
      }
    }
    return partialMatch
  }

  private static func pressableAncestor(of element: AXUIElement) -> AXUIElement? {
    var current: AXUIElement? = element
    for _ in 0..<4 {
      guard let currentElement = current else { return nil }
      var actions: CFArray?
      if AXUIElementCopyActionNames(currentElement, &actions) == .success,
         let names = actions as? [String], names.contains(kAXPressAction as String) { return current }
      var parent: CFTypeRef?
      guard AXUIElementCopyAttributeValue(currentElement, kAXParentAttribute as CFString, &parent) == .success else { return nil }
      current = (parent as! AXUIElement)
    }
    return nil
  }

  private static func isSearchField(_ element: AXUIElement) -> Bool {
    guard role(of: element) == kAXTextFieldRole as String else { return false }
    return text(of: element).contains("검색")
  }

  static func focusMessageInput(in root: AXUIElement) -> Bool {
    var queue = [root]
    var examined = 0
    var fallback: AXUIElement?
    while !queue.isEmpty, examined < 700 {
      let element = queue.removeFirst()
      examined += 1
      if isEditableTextInput(element), !isSearchField(element) {
        if text(of: element).contains("메시지") { return focus(element) }
        fallback = element
      }
      var children: CFTypeRef?
      if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
         let values = children as? [AXUIElement] {
        queue.append(contentsOf: values)
      }
    }
    return fallback.map(focus) ?? false
  }

  private static func isEditableTextInput(_ element: AXUIElement) -> Bool {
    let inputRoles = [kAXTextFieldRole as String, kAXTextAreaRole as String]
    return inputRoles.contains(role(of: element))
  }
}
