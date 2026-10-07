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

  /// Scheduled reports are the one push that carries a result: the user asked for exactly this,
  /// so a redacted, bounded excerpt is sent.
  static func scheduled(request: String, result: String, succeeded: Bool) -> PushNotification {
    let excerpt = SecretRedactor.redact(result).trimmingCharacters(in: .whitespacesAndNewlines)
    return PushNotification(title: "Aegis 예약: \(request.prefix(40))",
      message: excerpt.isEmpty ? (succeeded ? "완료했습니다." : "실행하지 못했습니다.") : String(excerpt.prefix(400)),
      priority: succeeded ? 3 : 4, tags: [succeeded ? "alarm_clock" : "x"])
  }

  static func watch(label: String, message: String, succeeded: Bool) -> PushNotification {
    PushNotification(title: "Aegis 감시: \(label)", message: message,
      priority: succeeded ? 4 : 3, tags: [succeeded ? "bell" : "hourglass"])
  }

  /// The note is the user's own words and the whole point of the reminder, so it is sent.
  static func reminder(_ note: String) -> PushNotification {
    PushNotification(title: "Aegis 리마인더", message: note, priority: 4, tags: ["alarm_clock"])
  }

  static func shouldNotifyFinish(startedAt: Date?, now: Date = .now, minimumSeconds: TimeInterval) -> Bool {
    guard let startedAt else { return false }
    return now.timeIntervalSince(startedAt) >= minimumSeconds
  }
}
