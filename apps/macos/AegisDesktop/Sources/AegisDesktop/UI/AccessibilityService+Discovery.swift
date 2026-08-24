import AppKit
import ApplicationServices
import Foundation

extension AccessibilityService {
  func windowElement(_ window: WindowDescriptor) throws -> AXUIElement {
    guard let bundle = window.bundleIdentifier,
      let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first
    else { throw UIInteractionError.applicationNotRunning(window.canonicalApplication) }
    let application = AXUIElementCreateApplication(app.processIdentifier)
    AXUIElementSetMessagingTimeout(application, 2)
    if bundle == "com.microsoft.VSCode" {
      _ = AXUIElementSetAttributeValue(application, "AXManualAccessibility" as CFString,
        kCFBooleanTrue)
    }
    let windows = attribute(application, kAXWindowsAttribute) as? [AXUIElement] ?? []
    guard let title = window.windowTitle, let match = windows.first(where: {
      (attribute($0, kAXTitleAttribute) as? String) == title
    }) else { throw UIInteractionError.windowNotFound(window.windowTitle ?? window.canonicalApplication) }
    return match
  }

  func elementTree(window: WindowDescriptor, maximumDepth: Int = 8,
                   maximumElements: Int = 300,
                   cancelled: () -> Bool = { false }) throws -> [AccessibilityTreeNode] {
    try requirePermissionForDiscovery()
    let root = try windowElement(window)
    var remaining = max(1, maximumElements), visited = Set<CFHashCode>()
    guard let node = treeNode(root, window: window, path: [], depth: 0,
      maximumDepth: max(0, maximumDepth), remaining: &remaining, visited: &visited,
      cancelled: cancelled) else { return [] }
    return [node]
  }

  func resolvedElement(_ descriptor: UIElementDescriptor,
                       window: WindowDescriptor) throws -> AXUIElement {
    guard descriptor.identifier != nil || descriptor.title != nil || descriptor.label != nil
    else { throw UIInteractionError.staleElement }
    let root = try windowElement(window)
    var found: AXUIElement?
    var inspected = 0, visited = Set<CFHashCode>()
    search(root, descriptor: descriptor, depth: 0, maximumDepth: 16,
      maximumElements: 300, inspected: &inspected, visited: &visited, found: &found)
    guard let found else { throw UIInteractionError.staleElement }
    return found
  }

  func collect(_ element: AXUIElement, window: WindowDescriptor, path: [String], depth: Int,
               maximumDepth: Int, maximumElements: Int,
               output: inout [UIElementDescriptor]) {
    guard depth <= maximumDepth, output.count < maximumElements else { return }
    let descriptor = describe(element, window: window, path: path)
    if descriptor.role != .unknown, descriptor.role != .staticText || descriptor.title != nil {
      output.append(descriptor)
    }
    let nextPath = Array((path + [descriptor.displayName]).suffix(6))
    for child in attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
      collect(child, window: window, path: nextPath, depth: depth + 1,
        maximumDepth: maximumDepth, maximumElements: maximumElements, output: &output)
      if output.count >= maximumElements { break }
    }
  }

  func describe(_ element: AXUIElement, window: WindowDescriptor,
                path: [String]) -> UIElementDescriptor {
    let roleValue = attribute(element, kAXRoleAttribute) as? String ?? ""
    let actions = actionNames(element)
    return UIElementDescriptor(id: UUID(), role: role(roleValue),
      subrole: attribute(element, kAXSubroleAttribute) as? String,
      identifier: bounded(attribute(element, kAXIdentifierAttribute) as? String),
      title: bounded(attribute(element, kAXTitleAttribute) as? String),
      label: bounded(attribute(element, kAXDescriptionAttribute) as? String),
      valueSummary: valueSummary(element), enabled: bool(element, kAXEnabledAttribute) ?? true,
      focused: bool(element, kAXFocusedAttribute) ?? false,
      valueSettable: isSettable(element, kAXValueAttribute),
      hasValueAttribute: attribute(element, kAXValueAttribute) != nil,
      applicationBundleIdentifier: window.bundleIdentifier ?? "unknown",
      windowIdentifier: window.id, windowTitle: window.windowTitle,
      parentPath: path, supportedActions: actions)
  }

  func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success
      ? value : nil
  }

  func bool(_ element: AXUIElement, _ name: String) -> Bool? {
    attribute(element, name) as? Bool
  }

  func elementAttribute(_ element: AXUIElement, _ name: String) -> AXUIElement? {
    guard let value = attribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID()
    else { return nil }
    return unsafeBitCast(value, to: AXUIElement.self)
  }

  private func isSettable(_ element: AXUIElement, _ name: String) -> Bool {
    var settable = DarwinBoolean(false)
    return AXUIElementIsAttributeSettable(element, name as CFString, &settable) == .success
      && settable.boolValue
  }

  private func search(_ element: AXUIElement, descriptor: UIElementDescriptor, depth: Int,
                      maximumDepth: Int, maximumElements: Int, inspected: inout Int,
                      visited: inout Set<CFHashCode>, found: inout AXUIElement?) {
    guard found == nil, depth <= maximumDepth, inspected < maximumElements else { return }
    guard visited.insert(CFHash(element)).inserted else { return }
    inspected += 1
    let candidate = describe(element, window: WindowDescriptor(id: descriptor.windowIdentifier ?? 0,
      applicationName: descriptor.applicationBundleIdentifier,
      bundleIdentifier: descriptor.applicationBundleIdentifier, windowTitle: descriptor.windowTitle,
      displayIndex: nil, isActive: false, isOnScreen: true,
      bounds: .init(x: 0, y: 0, width: 0, height: 0)), path: [])
    if candidate.role == descriptor.role,
      candidate.identifier == descriptor.identifier,
      candidate.title == descriptor.title, candidate.label == descriptor.label { found = element; return }
    for child in attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
      search(child, descriptor: descriptor, depth: depth + 1, maximumDepth: maximumDepth,
        maximumElements: maximumElements, inspected: &inspected, visited: &visited,
        found: &found)
    }
  }

  private func actionNames(_ element: AXUIElement) -> [String] {
    var names: CFArray?
    _ = AXUIElementCopyActionNames(element, &names)
    return (names as? [String] ?? []).prefix(12).map { $0 }
  }

  private func valueSummary(_ element: AXUIElement) -> String? {
    let subrole = (attribute(element, kAXSubroleAttribute) as? String ?? "").lowercased()
    guard !subrole.contains("secure"), !subrole.contains("password") else { return nil }
    return bounded(attribute(element, kAXValueAttribute) as? String)
  }

  private func bounded(_ value: String?) -> String? {
    value.map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160)) }
      .flatMap { $0.isEmpty ? nil : $0 }
  }

  private func role(_ value: String) -> UIElementRole {
    ["AXButton": .button, "AXTextField": .textField, "AXTextArea": .textArea,
     "AXSearchField": .searchField, "AXMenuItem": .menuItem, "AXMenu": .menu,
     "AXTabGroup": .tab, "AXCheckBox": .checkbox, "AXRadioButton": .radioButton,
     "AXPopUpButton": .popUpButton, "AXScrollArea": .scrollArea, "AXWindow": .window,
     "AXToolbar": .toolbar, "AXRow": .outlineRow, "AXStaticText": .staticText,
     "AXComboBox": .comboBox, "AXDialog": .dialog, "AXList": .list][value] ?? .unknown
  }

  private func treeNode(_ element: AXUIElement, window: WindowDescriptor, path: [String],
                        depth: Int, maximumDepth: Int, remaining: inout Int,
                        visited: inout Set<CFHashCode>, cancelled: () -> Bool)
    -> AccessibilityTreeNode? {
    guard remaining > 0, depth <= maximumDepth, !cancelled() else { return nil }
    let identity = CFHash(element)
    guard visited.insert(identity).inserted else { return nil }
    remaining -= 1
    let descriptor = describe(element, window: window, path: path)
    let rawChildren = attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    let nextPath = Array((path + [descriptor.displayName]).suffix(8))
    var children: [AccessibilityTreeNode] = []
    for child in rawChildren {
      if let node = treeNode(child, window: window, path: nextPath, depth: depth + 1,
        maximumDepth: maximumDepth, remaining: &remaining, visited: &visited,
        cancelled: cancelled) { children.append(node) }
      if remaining == 0 || cancelled() { break }
    }
    return AccessibilityTreeNode(descriptor: descriptor,
      accessibilityRole: attribute(element, kAXRoleAttribute) as? String,
      childCount: rawChildren.count, children: children)
  }

  private func requirePermissionForDiscovery() throws {
    guard availability() == .available else { throw UIInteractionError.permissionRequired }
  }
}
