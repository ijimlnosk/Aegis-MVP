import Foundation

enum MemoryIntentParser {
  static func parse(_ request: String) -> MemoryIntent? {
    let text = request.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.contains("뭘 기억") || text.contains("기억하고 있어") { return .list(type: nil) }
    if text.contains("프로젝트") && text.contains("기억") && text.contains("보여") { return .list(type: .project) }
    if text.contains("기본 브라우저") && ["뭐", "어떤", "알려"].contains(where: text.contains) {
      return .lookup(type: .preference, key: "default_browser")
    }
    if text.contains("기본 코드 에디터") && ["뭐", "어떤", "알려"].contains(where: text.contains) {
      return .lookup(type: .preference, key: "default_code_editor")
    }
    if ["지워", "잊어", "삭제"].contains(where: text.contains) {
      if text.contains("기본 브라우저") { return .forget(type: .preference, key: "default_browser") }
      if text.contains("기본 코드 에디터") { return .forget(type: .preference, key: "default_code_editor") }
      if text.contains("별칭"), let key = capture("^(.+?)\\s*(?:별칭|이라고)", in: text) {
        return .forget(type: .alias, key: key)
      }
    }
    if let alias = capture("^(.+?)(?:라고 하면|라 하면)\\s*([A-Za-z0-9_.-]+)", in: text, groups: 2) {
      return .remember(type: .alias, key: alias[0], value: alias[1])
    }
    if isBrowserTeaching(text), let browser = browserName(in: text) {
      return .remember(type: .preference, key: "default_browser", value: browser)
    }
    if (text.contains("기본 코드 에디터") || text.contains("기본 에디터")),
       let editor = editorName(in: text) {
      return .remember(type: .preference, key: "default_code_editor", value: editor)
    }
    if text.contains("기본 검증") {
      let checks = ["typecheck", "lint", "test", "build"].filter { text.lowercased().contains($0) }
      if !checks.isEmpty {
        return .remember(type: .preference, key: "preferred_project_health_checks",
          value: checks.joined(separator: ","))
      }
    }
    if text.contains("배포 전"),
      let project = capture("^([A-Za-z0-9_.-]+).*?배포 전", in: text) {
      let checks = ["typecheck", "lint", "test", "build"].filter { text.lowercased().contains($0) }
      if !checks.isEmpty {
        return .remember(type: .preference,
          key: "project_validation_profile:\(project.lowercased())", value: checks.joined(separator: ","))
      }
    }
    if text.contains("최근 커밋"), let count = capture("최근 커밋.*?([0-9]+)개", in: text) {
      return .remember(type: .preference, key: "recent_commit_count", value: count)
    }
    if let project = capture("^([A-Za-z0-9_.-]+).*?(?:내\\s*)?프로젝트", in: text) {
      let path = capture("경로(?:는|가)?\\s*(/\\S+?)(?:이야|야)?(?=\\s|$)", in: text)
      return .remember(type: .project, key: project, value: path ?? project)
    }
    if ["기억해", "알아둬"].contains(where: text.contains) {
      let value = text.replacingOccurrences(of: "기억해", with: "").replacingOccurrences(of: "알아둬", with: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
      if !value.isEmpty { return .remember(type: .fact, key: factKey(value), value: value) }
    }
    return nil
  }

  private static func isBrowserTeaching(_ text: String) -> Bool {
    (text.contains("앞으로") || text.contains("기본 브라우저")) &&
      (text.contains("써") || text.contains("사용") || text.contains("브라우저"))
  }

  private static func browserName(in text: String) -> String? {
    let names = ["Firefox", "Chrome", "Safari", "Arc", "Brave", "Edge"]
    let aliases = ["파이어폭스": "Firefox", "크롬": "Chrome", "사파리": "Safari"]
    if let value = names.first(where: { text.localizedCaseInsensitiveContains($0) }) { return value }
    return aliases.first(where: { text.contains($0.key) })?.value
  }

  private static func editorName(in text: String) -> String? {
    ["Visual Studio Code", "VSCode", "Cursor", "Xcode", "비주얼 스튜디오 코드", "커서", "엑스코드"]
      .compactMap(CodeEditorResolver.canonical).first { editor in
        text.localizedCaseInsensitiveContains(editor) ||
          (editor == "Visual Studio Code" && text.localizedCaseInsensitiveContains("VSCode")) ||
          (editor == "Cursor" && text.contains("커서")) || (editor == "Xcode" && text.contains("엑스코드"))
      }
  }

  private static func capture(_ pattern: String, in text: String) -> String? {
    capture(pattern, in: text, groups: 1)?.first
  }

  private static func capture(_ pattern: String, in text: String, groups: Int) -> [String]? {
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
    let values = (1...groups).compactMap { Range(match.range(at: $0), in: text).map { String(text[$0]) } }
    return values.count == groups ? values : nil
  }

  private static func factKey(_ value: String) -> String {
    String(value.lowercased().replacingOccurrences(of: " ", with: "_").prefix(48))
  }
}
