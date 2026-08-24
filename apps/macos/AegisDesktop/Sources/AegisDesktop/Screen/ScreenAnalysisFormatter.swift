import Foundation

enum ScreenAnalysisFormatter {
  static func format(snapshot: ScreenSnapshot, analysis: ScreenAnalysis,
                     projectContext: String?) -> String {
    var sections: [String] = []
    let application = useful(snapshot.canonicalApplication)
    let window = useful(snapshot.activeWindowTitle)
    let screen = [application.map { "- 앱: \($0)" }, window.map { "- 창: \($0)" }]
      .compactMap { $0 }
    if !screen.isEmpty { sections.append((["현재 화면"] + screen).joined(separator: "\n")) }

    let facts = limited(unique(lines(from: [analysis.visibleCodeContext,
      analysis.visibleUIState])), maximum: 8)
    if !facts.isEmpty { sections.append(section("확인된 내용", facts)) }

    let errors = limited(unique(analysis.visibleErrors), maximum: 5)
    if !errors.isEmpty { sections.append(section("오류", errors)) }
    let warnings = limited(unique(analysis.visibleWarnings), maximum: 5)
    if !warnings.isEmpty { sections.append(section("경고", warnings)) }

    if let inference = inference(analysis, snapshot: snapshot) {
      sections.append("해석\n- \(inference)")
    } else {
      sections.append("해석\n- 화면 분석 결과를 자연어로 정리하지 못했습니다.")
    }
    if let projectContext = useful(projectContext) {
      sections.append("신뢰된 프로젝트 상태\n\(projectContext)")
    }
    let limitations = limited(unique(analysis.limitations), maximum: 5)
    if !limitations.isEmpty { sections.append(section("제한", limitations)) }
    return sections.joined(separator: "\n\n")
  }

  private static func section(_ title: String, _ values: [String]) -> String {
    "\(title)\n" + values.map { "- \($0)" }.joined(separator: "\n")
  }

  private static func lines(from values: [String?]) -> [String] {
    values.compactMap { $0 }.flatMap {
      $0.components(separatedBy: .newlines).flatMap { line in
        line.split(separator: "•").map(String.init)
      }
    }.map(clean)
  }

  private static func unique(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.compactMap(presentable).filter { value in
      return seen.insert(value.lowercased()).inserted
    }
  }

  private static func limited(_ values: [String], maximum: Int) -> [String] {
    guard values.count > maximum else { return values }
    return Array(values.prefix(maximum)) + ["외 \(values.count - maximum)건"]
  }

  private static func clean(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: #"^[-*]\s*"#, with: "", options: .regularExpression)
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
  }

  private static func useful(_ value: String?) -> String? {
    guard let value else { return nil }
    let cleaned = clean(value)
    guard !cleaned.isEmpty,
      !["unknown", "null", "확인 불가", "알 수 없음", "없음"].contains(cleaned.lowercased())
    else { return nil }
    return cleaned
  }

  private static func presentable(_ value: String) -> String? {
    guard let cleaned = useful(value) else { return nil }
    let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !(trimmed.hasPrefix("{") || trimmed.hasPrefix("[")),
      !trimmed.contains(#"\"summary\""#) else { return nil }
    return String(trimmed.prefix(1_000))
  }

  private static func inference(_ analysis: ScreenAnalysis,
                                snapshot: ScreenSnapshot) -> String? {
    guard let summary = presentable(analysis.summary) else { return nil }
    let trusted = [snapshot.canonicalApplication, snapshot.activeWindowTitle].compactMap { $0 }
    let observations = [analysis.detectedApplication, analysis.detectedWindow].compactMap { $0 }
      .filter { observation in
        !trusted.contains { $0.caseInsensitiveCompare(observation) == .orderedSame }
      }
    guard !observations.contains(where: {
      summary.range(of: $0, options: .caseInsensitive) != nil
    }) else { return nil }
    return summary
  }
}
