import Foundation

enum SkillMatcher {
  static func match(_ request: String, skills: [LearnedSkill]) -> LearnedSkill? {
    let requestKey = normalize(request)
    guard !hasExplicitOverride(requestKey) else { return nil }
    return skills.filter { skill in
      ([skill.name] + skill.aliases).contains { alias in
        let key = normalize(alias)
        return requestKey == key || requestKey == key + " 해" || requestKey == key + " 실행"
      }
    }.sorted { $0.confidence == $1.confidence
      ? $0.updatedAt > $1.updatedAt : $0.confidence > $1.confidence }.first
  }

  static func normalize(_ value: String) -> String {
    var text = value.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    for suffix in ["해주세요", "해줘", "해 줘", "할래", "하자", "해", "요"] {
      if text.hasSuffix(suffix) { text = String(text.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces) }
    }
    return text
  }

  private static func hasExplicitOverride(_ request: String) -> Bool {
    ["하지 말", "하지마", "말고", "대신"].contains(where: request.contains)
  }
}
