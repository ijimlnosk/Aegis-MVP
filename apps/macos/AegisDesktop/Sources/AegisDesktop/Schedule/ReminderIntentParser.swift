import Foundation

enum ReminderIntent: Equatable {
  case create(Reminder.Content, fireAt: Date)
  case list
  case cancel(index: Int)
}

/// "30분 뒤에 배포 확인하라고 알려줘", "1시간 후에 알려줘", "오후 3시에 PTFriends 상태 알려줘",
/// "내일 아침 9시 반에 회의 준비하라고 알려줘", "리마인더 목록", "리마인더 1번 취소".
/// Daily ("매일") requests belong to ScheduleIntentParser and "끝나면" to WatchIntentParser.
enum ReminderIntentParser {
  private static let relative = #"^(\d{1,3})\s*(분|시간)\s*(?:뒤|후)에?\s*(.*?)\s*알려\s*(?:줘|주세요)?\s*[.!?]?$"#
  private static let absolute =
    #"^(오늘|내일)?\s*(오전|아침|새벽|오후|저녁|밤)?\s*(?:(\d{1,2})\s*:\s*(\d{2})|(\d{1,2})\s*시\s*(?:(\d{1,2})\s*분|(반))?)\s*에\s*(.*?)\s*알려\s*(?:줘|주세요)?\s*[.!?]?$"#

  static func parse(_ text: String, now: Date = .now, calendar: Calendar = .current) -> ReminderIntent? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let compact = trimmed.replacingOccurrences(of: " ", with: "")
    if ["리마인더목록", "리마인더보여줘", "알림예약목록"].contains(where: compact.hasPrefix) { return .list }
    if let match = compact.firstMatch(of: #/^리마인더(\d{1,2})번(?:취소|삭제)/#), let index = Int(match.1) {
      return .cancel(index: index)
    }
    guard !trimmed.hasPrefix("매일"), !trimmed.hasPrefix("평일"), !trimmed.contains("끝나면") else { return nil }
    if let groups = match(relative, trimmed), let amount = Int(groups[1] ?? ""), amount > 0 {
      let seconds = Double(amount) * (groups[2] == "시간" ? 3600 : 60)
      guard seconds <= 7 * 86_400 else { return nil }
      return .create(content(groups[3] ?? ""), fireAt: now.addingTimeInterval(seconds))
    }
    guard let groups = match(absolute, trimmed), let rawHour = Int(groups[3] ?? groups[5] ?? "") else { return nil }
    let minute = Int(groups[4] ?? groups[6] ?? "") ?? (groups[7] == nil ? 0 : 30)
    var hour = rawHour
    if ["오후", "저녁", "밤"].contains(groups[2] ?? ""), hour < 12 { hour += 12 }
    guard (0...23).contains(hour), (0...59).contains(minute),
      var fireAt = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) else { return nil }
    if groups[1] == "내일" || (groups[1] == nil && fireAt <= now) {
      fireAt = calendar.date(byAdding: .day, value: 1, to: fireAt) ?? fireAt
    }
    guard fireAt > now else { return nil }
    return .create(content(groups[8] ?? ""), fireAt: fireAt)
  }

  /// "…하라고"/"…라고" marks a note to deliver; anything else is a request to run.
  static func content(_ body: String) -> Reminder.Content {
    let text = body.trimmingCharacters(in: .whitespaces)
    for suffix in ["하라고", "이라고", "라고"] where text.hasSuffix(suffix) {
      return .note(String(text.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces))
    }
    return text.isEmpty ? .note("") : .request(text + " 알려줘")
  }

  private static func match(_ pattern: String, _ text: String) -> [String?]? {
    guard let regex = try? NSRegularExpression(pattern: pattern),
      let result = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
    return (0..<result.numberOfRanges).map { Range(result.range(at: $0), in: text).map { String(text[$0]) } }
  }
}
