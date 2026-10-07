import Foundation

enum ProjectCodeIntent: Equatable {
  case search(project: String, query: String)
  case read(project: String, file: String)
}

/// "PTFriends에서 login 찾아줘" searches; "SoolSool README 보여줘" reads a tracked file.
enum ProjectCodeIntentParser {
  private static let searchPattern = #"^(.+?)에서\s+(.+?)\s*(?:을|를)?\s*(?:찾아|검색|어디)"#
  /// Requests for judgement belong to the Codex analysis path, not a text search.
  private static let analysisWords = ["개선", "문제점", "버그", "리뷰", "분석", "추천", "변경하면", "바꾸면"]
  private static let fillerWords = ["함수", "파일", "코드", "부분", "정의", "위치", "사용처", "쓰는 곳", "문자열", "텍스트"]
  private static let readVerbs = ["보여줘", "보여 줘", "열어줘", "읽어줘", "내용"]
  private static let wellKnownFiles = ["readme", "changelog", "license", "dockerfile", "makefile"]

  static func parse(_ text: String, project resolve: (String) -> String?) -> ProjectCodeIntent? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if let search = search(trimmed, resolve) { return search }
    guard readVerbs.contains(where: trimmed.contains), let project = resolve(trimmed),
      let file = fileToken(in: trimmed) else { return nil }
    return .read(project: project, file: file)
  }

  private static func search(_ text: String, _ resolve: (String) -> String?) -> ProjectCodeIntent? {
    guard let regex = try? NSRegularExpression(pattern: searchPattern),
      let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
      let projectRange = Range(match.range(at: 1), in: text), let queryRange = Range(match.range(at: 2), in: text),
      let project = resolve(String(text[projectRange])) else { return nil }
    let raw = String(text[queryRange])
    guard !analysisWords.contains(where: raw.contains) else { return nil }
    let query = searchTerm(from: raw)
    return query.count >= 2 ? .search(project: project, query: query) : nil
  }

  /// Prefers an identifier ("login", "useAuth") over surrounding Korean filler words.
  static func searchTerm(from raw: String) -> String {
    let identifiers = raw.split(whereSeparator: { $0 == " " }).map(String.init)
      .filter { $0.range(of: #"^[A-Za-z_$][\w.$-]+$"#, options: .regularExpression) != nil }
    if let identifier = identifiers.first { return identifier }
    let cleaned = fillerWords.reduce(raw) { $0.replacingOccurrences(of: $1, with: " ") }
    return cleaned.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'‘’“”")))
  }

  private static func fileToken(in text: String) -> String? {
    text.split(separator: " ").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"'‘’“”,")) }
      .first { token in
        token.contains("/") || token.range(of: #"^[\w.-]+\.[A-Za-z0-9]{1,8}$"#, options: .regularExpression) != nil
          || wellKnownFiles.contains(token.lowercased())
      }
  }
}
