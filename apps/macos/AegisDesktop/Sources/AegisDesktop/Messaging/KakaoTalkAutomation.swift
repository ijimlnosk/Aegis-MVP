import AppKit
import ApplicationServices
import Foundation

struct KakaoMessage {
  let recipient: String
  let body: String
}

enum KakaoTalkAutomation {
  static func send(_ message: KakaoMessage) async -> String {
    await Task.detached {
      guard CGPreflightPostEventAccess() || CGRequestPostEventAccess() else {
        return "Aegis의 기기 제어 권한이 필요합니다."
      }
      let recipient = message.recipient.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
      guard let app = await openKakaoIfNeeded() else {
        return "카카오톡을 실행하지 못했습니다."
      }
      LearningStore.rememberApplication(alias: "카카오톡", bundleID: "com.kakao.KakaoTalkMac", displayName: app.localizedName ?? "KakaoTalk")
      app.activate(options: [])
      try? await Task.sleep(for: .seconds(1))
      let application = AXUIElementCreateApplication(app.processIdentifier)
      dismissCurrentChatIfSeparateWindow(in: application)
      try? await Task.sleep(for: .milliseconds(500))
      guard openGlobalChatSearch(in: application) else {
        return "카카오톡의 전체 채팅 검색 버튼을 찾지 못했습니다. 전송하지 않았습니다."
      }
      try? await Task.sleep(for: .milliseconds(500))
      KakaoInput.shortcut(0, flags: .maskCommand)
      KakaoInput.shortcut(51)
      KakaoInput.paste(recipient)
      try? await Task.sleep(for: .seconds(1))
      guard let result = KakaoAccessibility.matchingElement(named: recipient, in: application), KakaoAccessibility.activate(result) else {
        return "‘\(recipient)’ 검색 결과를 카카오톡에서 찾지 못했습니다. 전송하지 않았습니다."
      }
      try? await Task.sleep(for: .milliseconds(200))
      KakaoInput.shortcut(36)
      try? await Task.sleep(for: .seconds(2))
      let chatWindow = KakaoAccessibility.focusedWindow(of: application) ?? application
      guard KakaoAccessibility.focusMessageInput(in: chatWindow) else {
        return "‘\(recipient)’ 대화방은 열었지만 메시지 입력창을 찾지 못했습니다. 전송하지 않았습니다."
      }
      try? await Task.sleep(for: .milliseconds(200))
      KakaoInput.paste(message.body)
      try? await Task.sleep(for: .milliseconds(250))
      guard KakaoAccessibility.focusedTextContains(message.body, in: application) else {
        return "메시지 입력을 확인하지 못했습니다. 전송하지 않았습니다."
      }
      KakaoInput.shortcut(36)
      return "\(recipient) 대화방에 메시지를 입력하고 전송했습니다."
    }.value
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
    KakaoInput.shortcut(53)
    KakaoInput.shortcut(13, flags: .maskCommand)
  }

  private static func openGlobalChatSearch(in application: AXUIElement) -> Bool {
    guard let window = KakaoAccessibility.mainWindow(in: application), let frame = KakaoAccessibility.frame(of: window) else { return false }
    let point = CGPoint(x: frame.origin.x + frame.size.width - 72, y: frame.origin.y + 28)
    return KakaoInput.click(at: point)
  }
}
