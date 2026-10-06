import Foundation

enum ScheduleIntent: Equatable {
  case create(request: String, hour: Int, minute: Int, weekdaysOnly: Bool)
  case list
  case delete(index: Int)
}

/// "매일 아침 9시에 PTFriends 상태 알려줘", "평일 18:30에 sol-server 상태 보여줘",
/// "예약 목록 보여줘", "예약 2번 삭제".
enum ScheduleIntentParser {
  private static let timePattern =
    #"^(매일|평일)\s*(오전|아침|새벽|오후|저녁|밤)?\s*(?:(\d{1,2})\s*:\s*(\d{2})|(\d{1,2})\s*시\s*(?:(\d{1,2})\s*분|(반))?)\s*(?:마다|에)\s+(.+)$"#

  static func parse(_ text: String) -> ScheduleIntent? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let compact = trimmed.replacingOccurrences(of: " ", with: "")
    if ["예약목록", "예약보여줘", "예약확인", "예약된작업"].contains(where: compact.hasPrefix) { return .list }
    if let match = compact.firstMatch(of: #/^예약(\d{1,2})번(?:삭제|취소|지워)/#), let index = Int(match.1) {
      return .delete(index: index)
    }
    return create(trimmed)
  }

  private static func create(_ text: String) -> ScheduleIntent? {
    guard let regex = try? NSRegularExpression(pattern: timePattern),
      let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
    func group(_ index: Int) -> String? {
      Range(match.range(at: index), in: text).map { String(text[$0]) }
    }
    guard let rawHour = Int(group(3) ?? group(5) ?? ""), let request = group(8)?
      .trimmingCharacters(in: .whitespacesAndNewlines), !request.isEmpty else { return nil }
    let minute = Int(group(4) ?? group(6) ?? "") ?? (group(7) == nil ? 0 : 30)
    var hour = rawHour
    if ["오후", "저녁", "밤"].contains(group(2) ?? ""), hour < 12 { hour += 12 }
    guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
    return .create(request: request, hour: hour, minute: minute, weekdaysOnly: group(1) == "평일")
  }
}
