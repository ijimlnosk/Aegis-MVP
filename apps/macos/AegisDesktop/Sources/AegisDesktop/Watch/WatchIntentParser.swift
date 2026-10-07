import Foundation

enum WatchIntent: Equatable {
  case create(WatchKind)
  case list
  case cancel(index: Int)
}

/// "PTFriends CI 끝나면 알려줘", "sol-server 복구되면 알려줘", "감시 목록", "감시 1번 취소".
enum WatchIntentParser {
  private static let finished = ["끝나면", "완료되면", "끝나면은", "다 돌면"]
  private static let recovered = ["복구되면", "살아나면", "돌아오면", "연결되면", "다시 켜지면", "켜지면"]

  static func parse(_ text: String, project: (String) -> String?) -> WatchIntent? {
    let compact = text.replacingOccurrences(of: " ", with: "").lowercased()
    if ["감시목록", "감시보여줘", "감시중인", "알림조건목록"].contains(where: compact.hasPrefix) { return .list }
    if let match = compact.firstMatch(of: #/^감시(\d{1,2})번(?:취소|삭제|그만)/#), let index = Int(match.1) {
      return .cancel(index: index)
    }
    guard compact.contains("알려") else { return nil }
    let lowered = text.lowercased()
    if compact.contains("ci"), finished.contains(where: { lowered.contains($0) }), let name = project(text) {
      return .create(.ciFinished(project: name))
    }
    if compact.contains("sol-server") || compact.contains("서버"),
      recovered.contains(where: { lowered.contains($0) }) {
      return .create(.serverReachable)
    }
    return nil
  }
}
