import Foundation

/// Push wording. Bodies name actions and projects only; they never carry the request text,
/// message bodies, command output, or evidence, because a push leaves the Mac.
enum PushMessages {
  static func approval(kind: String, scope: String) -> PushNotification {
    let presentation = ApprovalPresentation.present(kind: kind)
    return PushNotification(title: "Aegis 승인 필요", message: "\(scope): \(presentation.effect)",
      priority: 4, tags: [presentation.irreversible ? "warning" : "bell"])
  }

  static func finished(succeeded: Bool, actions: [AgentAction], project: String?) -> PushNotification {
    let names = actions.map(\.displayName).joined(separator: " → ")
    let prefix = project.map { "\($0): " } ?? ""
    return PushNotification(title: succeeded ? "Aegis 작업 완료" : "Aegis 작업 실패",
      message: prefix + (names.isEmpty ? "요청한 작업" : names),
      priority: succeeded ? 3 : 4, tags: [succeeded ? "white_check_mark" : "x"])
  }

  static func proactive(_ event: ProactiveEvent) -> PushNotification {
    let priority = switch event.severity { case .critical: 5; case .warning: 4; case .info: 2 }
    return PushNotification(title: event.severity == .info ? "Aegis 알림" : "Aegis 경고",
      message: event.title, priority: priority, tags: [event.severity == .info ? "information_source" : "rotating_light"])
  }

  static func shouldNotifyFinish(startedAt: Date?, now: Date = .now, minimumSeconds: TimeInterval) -> Bool {
    guard let startedAt else { return false }
    return now.timeIntervalSince(startedAt) >= minimumSeconds
  }
}
