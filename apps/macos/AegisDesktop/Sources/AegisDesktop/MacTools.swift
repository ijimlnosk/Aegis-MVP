import AppKit

enum MacTools {
  static func activeApplication() -> String {
    guard let application = NSWorkspace.shared.frontmostApplication else {
      return "현재 활성 앱을 확인하지 못했습니다."
    }
    return "현재 활성 앱은 \(application.localizedName ?? "알 수 없는 앱")입니다."
  }
}
