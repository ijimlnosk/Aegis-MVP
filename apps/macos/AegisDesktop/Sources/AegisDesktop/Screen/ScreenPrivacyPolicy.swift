enum ScreenPrivacyDecision: Equatable { case allowed, blocked(String) }

enum ScreenPrivacyPolicy {
  static let sensitiveApplications = ["1Password", "Keychain Access", "Passwords",
    "System Settings", "시스템 설정", "Authy"]

  static func decision(for application: String?) -> ScreenPrivacyDecision {
    guard let application else { return .allowed }
    if sensitiveApplications.contains(where: { application.localizedCaseInsensitiveContains($0) }) {
      return .blocked("현재 \(application) 창은 민감한 앱으로 분류되어 화면을 캡처하지 않았습니다.")
    }
    return .allowed
  }
}
