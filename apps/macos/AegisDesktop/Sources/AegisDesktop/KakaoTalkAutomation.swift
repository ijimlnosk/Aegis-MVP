import AppKit
import ApplicationServices
import Foundation

struct KakaoMessage {
  let recipient: String
  let body: String
}

enum KakaoTalkAutomation {
  static func message(from text: String) -> KakaoMessage? {
    guard text.contains("카카오톡") else { return nil }
    let pattern = "(?:카카오톡(?:으로|에서)?\\s*)?(.+?)(?:(?:에게|한테)|(?:\\s*채팅방)?에)\\s+(.+?)(?:이라고\\s*)?(?:보내(?:\\s*줘)?|전송(?:\\s*해)?(?:\\s*줘)?|전달(?:\\s*해)?(?:\\s*줘)?)$"
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
          let recipientRange = Range(match.range(at: 1), in: text),
          let bodyRange = Range(match.range(at: 2), in: text) else { return nil }
    let recipient = String(text[recipientRange]).trimmingCharacters(in: .whitespaces)
    return KakaoMessage(recipient: normalizedRecipient(recipient), body: String(text[bodyRange]).trimmingCharacters(in: .whitespaces))
  }

  static func send(_ message: KakaoMessage) async -> String {
    await Task.detached {
      guard CGPreflightPostEventAccess() || CGRequestPostEventAccess() else {
        return "Aegis의 기기 제어 권한이 필요합니다."
      }
      let recipient = message.recipient.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
      guard let app = await openKakaoIfNeeded() else {
        return "카카오톡을 실행하지 못했습니다."
      }
      app.activate(options: [])
      try? await Task.sleep(for: .seconds(1))
      let application = AXUIElementCreateApplication(app.processIdentifier)
      dismissCurrentChatIfSeparateWindow(in: application)
      try? await Task.sleep(for: .milliseconds(500))
      guard openGlobalChatSearch(in: application) else {
        return "카카오톡의 전체 채팅 검색 버튼을 찾지 못했습니다. 전송하지 않았습니다."
      }
      try? await Task.sleep(for: .milliseconds(500))
      shortcut(0, flags: .maskCommand)
      shortcut(51)
      paste(recipient)
      try? await Task.sleep(for: .seconds(1))
      guard let result = matchingElement(named: recipient, in: application), activate(result) else {
        return "‘\(recipient)’ 검색 결과를 카카오톡에서 찾지 못했습니다. 전송하지 않았습니다."
      }
      try? await Task.sleep(for: .milliseconds(200))
      shortcut(36)
      try? await Task.sleep(for: .seconds(2))
      let chatWindow = focusedWindow(of: application) ?? application
      guard focusMessageInput(in: chatWindow) else {
        return "‘\(recipient)’ 대화방은 열었지만 메시지 입력창을 찾지 못했습니다. 전송하지 않았습니다."
      }
      try? await Task.sleep(for: .milliseconds(200))
      paste(message.body)
      try? await Task.sleep(for: .milliseconds(250))
      guard focusedTextContains(message.body, in: application) else {
        return "메시지 입력을 확인하지 못했습니다. 전송하지 않았습니다."
      }
      shortcut(36)
      return "\(recipient) 대화방에 메시지를 입력하고 전송했습니다."
    }.value
  }

  private static func paste(_ text: String) {
    let board = NSPasteboard.general
    board.clearContents()
    board.setString(text, forType: .string)
    shortcut(9, flags: .maskCommand)
  }

  private static func shortcut(_ key: CGKeyCode, flags: CGEventFlags = []) {
    guard let source = CGEventSource(stateID: .hidSystemState),
          let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
          let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else { return }
    down.flags = flags
    up.flags = flags
    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
  }

  private static func openKakaoIfNeeded() async -> NSRunningApplication? {
    if let running = NSRunningApplication.runningApplications(withBundleIdentifier: "com.kakao.KakaoTalkMac").first {
      if !hasVisibleWindow(for: running) { await requestKakaoWindow() }
      return running
    }
    await requestKakaoWindow()
    for _ in 0..<10 {
      if let running = NSRunningApplication.runningApplications(withBundleIdentifier: "com.kakao.KakaoTalkMac").first {
        return running
      }
      try? await Task.sleep(for: .milliseconds(300))
    }
    return nil
  }

  private static func requestKakaoWindow() async {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.kakao.KakaoTalkMac") else { return }
    var configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    try? await Task.sleep(for: .milliseconds(700))
  }

  private static func hasVisibleWindow(for app: NSRunningApplication) -> Bool {
    let application = AXUIElementCreateApplication(app.processIdentifier)
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value) == .success,
          let windows = value as? [AXUIElement] else { return true }
    return !windows.isEmpty
  }

  private static func dismissCurrentChatIfSeparateWindow(in application: AXUIElement) {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value) == .success,
          let windows = value as? [AXUIElement], windows.count > 1 else { return }
    shortcut(53)
    shortcut(13, flags: .maskCommand)
  }

  private static func openGlobalChatSearch(in application: AXUIElement) -> Bool {
    guard let window = mainWindow(in: application), let frame = frame(of: window) else { return false }
    let point = CGPoint(x: frame.origin.x + frame.size.width - 72, y: frame.origin.y + 28)
    return click(at: point)
  }

  private static func mainWindow(in application: AXUIElement) -> AXUIElement? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value) == .success,
          let windows = value as? [AXUIElement] else { return nil }
    return windows.max { (frame(of: $0)?.size.width ?? 0) * (frame(of: $0)?.size.height ?? 0)
      < (frame(of: $1)?.size.width ?? 0) * (frame(of: $1)?.size.height ?? 0) }
  }

  private static func frame(of element: AXUIElement) -> CGRect? {
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

  private static func click(at point: CGPoint) -> Bool {
    guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
          let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else { return false }
    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
    return true
  }

  private static func matchingElement(named name: String, in root: AXUIElement) -> AXUIElement? {
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

  private static func activate(_ element: AXUIElement) -> Bool {
    if AXUIElementPerformAction(element, kAXPressAction as CFString) == .success { return true }
    var positionValue: CFTypeRef?
    var sizeValue: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
          AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
          positionValue != nil, sizeValue != nil else { return false }
    let position = positionValue! as! AXValue
    let size = sizeValue! as! AXValue
    var point = CGPoint.zero
    var dimensions = CGSize.zero
    guard AXValueGetValue(position, .cgPoint, &point), AXValueGetValue(size, .cgSize, &dimensions) else { return false }
    let target = CGPoint(x: point.x + dimensions.width / 2, y: point.y + dimensions.height / 2)
    guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: target, mouseButton: .left),
          let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: target, mouseButton: .left) else { return false }
    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
    return true
  }

  private static func isSearchField(_ element: AXUIElement) -> Bool {
    guard role(of: element) == kAXTextFieldRole as String else { return false }
    return text(of: element).contains("검색")
  }

  private static func focusMessageInput(in root: AXUIElement) -> Bool {
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

  private static func focusedWindow(of application: AXUIElement) -> AXUIElement? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &value) == .success else { return nil }
    return value as! AXUIElement?
  }

  private static func focusedTextContains(_ expected: String, in application: AXUIElement) -> Bool {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute as CFString, &value) == .success,
          let element = value as! AXUIElement? else { return false }
    return normalized(text(of: element)).contains(normalized(expected))
  }

  private static func isEditableTextInput(_ element: AXUIElement) -> Bool {
    let inputRoles = [kAXTextFieldRole as String, kAXTextAreaRole as String]
    return inputRoles.contains(role(of: element))
  }

  private static func focus(_ element: AXUIElement) -> Bool {
    if AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success { return true }
    return activate(element)
  }

  private static func role(of element: AXUIElement) -> String {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) == .success else { return "" }
    return value as? String ?? ""
  }

  private static func text(of element: AXUIElement) -> String {
    [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute, kAXPlaceholderValueAttribute]
      .compactMap { attribute -> String? in
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
      }
      .joined(separator: " ")
  }

  private static func normalized(_ text: String) -> String {
    text.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
  }

  private static func normalizedRecipient(_ recipient: String) -> String {
    guard recipient.range(of: "^[가-힣\\s]+$", options: .regularExpression) != nil else { return recipient }
    return recipient.components(separatedBy: .whitespaces).joined()
  }
}
