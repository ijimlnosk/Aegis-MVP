import AppKit
import ApplicationServices
import Foundation

struct AccessibilityService: @unchecked Sendable {
  private let permissionProvider: @Sendable () -> AccessibilityAvailability

  init(permissionProvider: @escaping @Sendable () -> AccessibilityAvailability = {
    AccessibilityPermission.status()
  }) { self.permissionProvider = permissionProvider }

  func availability(prompt: Bool = false) -> AccessibilityAvailability {
    prompt ? AccessibilityPermission.status(prompt: true) : permissionProvider()
  }

  func activate(_ application: KnownApplication) throws -> String {
    try requirePermission()
    guard let running = application.bundleIdentifiers.lazy.compactMap({
      NSRunningApplication.runningApplications(withBundleIdentifier: $0).first
    }).first else { throw UIInteractionError.applicationNotRunning(application.canonicalName) }
    running.activate()
    for _ in 0..<10 where NSWorkspace.shared.frontmostApplication?.processIdentifier
      != running.processIdentifier {
      RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == running.processIdentifier
    else { throw UIInteractionError.verificationFailed }
    return "\(application.canonicalName)을 앞으로 가져왔습니다."
  }

  func focus(window: WindowDescriptor) throws -> String {
    try requirePermission()
    guard let bundle = window.bundleIdentifier,
      let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first
    else { throw UIInteractionError.applicationNotRunning(window.canonicalApplication) }
    running.activate()
    let element = try windowElement(window)
    guard AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString,
      kCFBooleanTrue) == .success,
      AXUIElementPerformAction(element, kAXRaiseAction as CFString) == .success
    else { throw UIInteractionError.unsupportedAction }
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == running.processIdentifier,
      bool(element, kAXMainAttribute) == true || bool(element, kAXFocusedAttribute) == true
    else { throw UIInteractionError.verificationFailed }
    return "\(window.canonicalApplication) · \(window.windowTitle ?? "창")으로 전환했습니다."
  }

  func close(window: WindowDescriptor) throws -> String {
    try requirePermission()
    let element = try windowElement(window)
    guard let button = elementAttribute(element, kAXCloseButtonAttribute),
      AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
    else { throw UIInteractionError.unsupportedAction }
    for _ in 0..<10 where (try? windowElement(window)) != nil {
      RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    guard (try? windowElement(window)) == nil else { throw UIInteractionError.verificationFailed }
    return "\(window.windowTitle ?? window.canonicalApplication) 창을 닫았습니다."
  }

  func listElements(window: WindowDescriptor, maximumDepth: Int = 5,
                    maximumElements: Int = 40) throws -> [UIElementDescriptor] {
    try requirePermission()
    let root = try windowElement(window)
    var output: [UIElementDescriptor] = []
    collect(root, window: window, path: [], depth: 0, maximumDepth: maximumDepth,
      maximumElements: maximumElements, output: &output)
    return output
  }

  func press(_ descriptor: UIElementDescriptor, window: WindowDescriptor) throws -> String {
    try requirePermission()
    let element = try resolvedElement(descriptor, window: window)
    guard descriptor.enabled, descriptor.role.actionable else { throw UIInteractionError.disabled }
    guard AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    else { throw UIInteractionError.unsupportedAction }
    return "\(descriptor.displayName)을 눌렀습니다."
  }

  func focus(_ descriptor: UIElementDescriptor, window: WindowDescriptor) throws -> String {
    try requirePermission()
    let element = try resolvedElement(descriptor, window: window)
    guard AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString,
      kCFBooleanTrue) == .success else { throw UIInteractionError.unsupportedAction }
    guard bool(element, kAXFocusedAttribute) == true else {
      throw UIInteractionError.verificationFailed
    }
    return "\(descriptor.displayName)에 포커스를 맞췄습니다."
  }

  func setText(_ text: String, append: Bool, descriptor: UIElementDescriptor,
               window: WindowDescriptor) throws -> String {
    try requirePermission()
    try UIInteractionPolicy.validateTextTarget(descriptor)
    let element = try resolvedElement(descriptor, window: window)
    let previous = append ? (attribute(element, kAXValueAttribute) as? String ?? "") : ""
    let expected = previous + text
    _ = AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString,
      kCFBooleanTrue)
    guard AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString,
      expected as CFTypeRef) == .success else { throw UIInteractionError.unsupportedAction }
    for _ in 0..<10 where attribute(element, kAXValueAttribute) as? String != expected {
      RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    guard attribute(element, kAXValueAttribute) as? String == expected else {
      throw UIInteractionError.verificationFailed
    }
    return "\(descriptor.displayName)에 텍스트를 \(append ? "추가" : "입력")했습니다."
  }

  func shortcut(_ shortcut: KeyboardShortcut, window: WindowDescriptor) throws -> String {
    _ = try focus(window: window)
    let mapping = shortcut.mapping
    guard let source = CGEventSource(stateID: .hidSystemState),
      let down = CGEvent(keyboardEventSource: source, virtualKey: mapping.key, keyDown: true),
      let up = CGEvent(keyboardEventSource: source, virtualKey: mapping.key, keyDown: false)
    else { throw UIInteractionError.unsupportedAction }
    down.flags = mapping.flags; up.flags = mapping.flags
    down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
    RunLoop.current.run(until: Date().addingTimeInterval(0.15))
    guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier
      == window.bundleIdentifier else { throw UIInteractionError.verificationFailed }
    return "\(shortcut.rawValue) 단축키를 실행했습니다."
  }

  func scroll(_ direction: UIScrollDirection, window: WindowDescriptor) throws -> String {
    try requirePermission()
    let elements = try listElements(window: window)
    let areas = elements.filter { $0.role == .scrollArea && $0.enabled }
    let focusedAreas = areas.filter(\.focused)
    let area: UIElementDescriptor
    if focusedAreas.count == 1 { area = focusedAreas[0] }
    else if areas.count == 1 { area = areas[0] }
    else if areas.isEmpty { throw UIInteractionError.targetNotFound("스크롤 영역") }
    else { throw UIInteractionError.ambiguousTarget("스크롤 영역") }
    let element = try resolvedElement(area, window: window)
    let actions: [UIScrollDirection: String] = [.up: "AXScrollUpByPage",
      .down: "AXScrollDownByPage", .left: "AXScrollLeftByPage", .right: "AXScrollRightByPage"]
    guard let action = actions[direction],
      AXUIElementPerformAction(element, action as CFString) == .success
    else { throw UIInteractionError.unsupportedAction }
    return "\(direction.rawValue) 방향으로 스크롤했습니다."
  }

  private func requirePermission() throws {
    guard availability() == .available else { throw UIInteractionError.permissionRequired }
  }
}

private extension KeyboardShortcut {
  var mapping: (key: CGKeyCode, flags: CGEventFlags) {
    switch self {
    case .quickOpen: (35, .maskCommand)
    case .commandPalette: (35, [.maskCommand, .maskShift])
    case .find: (3, .maskCommand)
    case .closeWindow: (13, .maskCommand)
    case .escape: (53, [])
    case .confirm: (36, [])
    case .nextTab: (48, .maskControl)
    case .previousTab: (48, [.maskControl, .maskShift])
    }
  }
}
