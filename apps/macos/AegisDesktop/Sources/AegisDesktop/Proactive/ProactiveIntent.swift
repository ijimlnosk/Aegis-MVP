import Foundation

enum ProactiveIntent {
  case status
  case diagnostics
  case quiet(duration: TimeInterval, scope: QuietScope)
  case resume
  case threshold(key: String, value: Double)
  case suppressLast
}

enum ProactiveIntentParser {
  static func parse(_ request: String) -> ProactiveIntent? {
    let text = request.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    if text.contains("지금 뭐 문제") || text.contains("현재 문제") { return .status }
    if text.contains("context 진단") || text.contains("관찰 상태") { return .diagnostics }
    if text.contains("다시 알려") || text.contains("알림 다시") { return .resume }
    if text.contains("이런 건") && text.contains("알려주지 마") { return .suppressLast }
    if text.contains("알림") && (text.contains("하지 마") || text.contains("꺼")) {
      if text.contains("한 시간") { return .quiet(duration: 3600, scope: .all) }
      if text.contains("오늘") {
        let end = Calendar.current.startOfDay(for: .now).addingTimeInterval(86_400)
        return .quiet(duration: end.timeIntervalSinceNow, scope: text.contains("서버") ? .server : .all)
      }
    }
    if let value = percentage(text) {
      if text.contains("디스크") { return .threshold(key: "alert_disk_percent", value: value) }
      if text.contains("메모리") { return .threshold(key: "alert_memory_percent", value: value) }
    }
    if text.contains("변경 파일"), let value = firstNumber(text) {
      let project = text.split(separator: " ").first.map(String.init) ?? "default"
      return .threshold(key: "alert_project_\(project.lowercased())_files", value: value)
    }
    return nil
  }

  private static func percentage(_ text: String) -> Double? {
    guard let match = text.range(of: #"\d+(?:\.\d+)?\s*%"#, options: .regularExpression) else { return nil }
    return Double(text[match].filter { $0.isNumber || $0 == "." })
  }
  private static func firstNumber(_ text: String) -> Double? {
    guard let match = text.range(of: #"\d+"#, options: .regularExpression) else { return nil }
    return Double(text[match])
  }
}
