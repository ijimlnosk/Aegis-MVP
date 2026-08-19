struct ScreenInspectionResult: Equatable {
  let message: String
  let historySummary: String
  let succeeded: Bool

  static func format(snapshot: ScreenSnapshot, analysis: ScreenAnalysis,
                     projectContext: String?) -> Self {
    var sections = ["현재 화면", "- 앱: \(snapshot.activeApplication ?? "확인 불가")",
      "- 창: \(snapshot.activeWindowTitle ?? "확인 불가")", "", "확인된 내용", analysis.summary]
    if !analysis.visibleErrors.isEmpty { sections += ["", "오류", analysis.visibleErrors.map { "- \($0)" }.joined(separator: "\n")] }
    if !analysis.visibleWarnings.isEmpty { sections += ["", "경고", analysis.visibleWarnings.map { "- \($0)" }.joined(separator: "\n")] }
    if let projectContext { sections += ["", "신뢰된 프로젝트 상태", projectContext] }
    if !analysis.limitations.isEmpty { sections += ["", "제한", analysis.limitations.map { "- \($0)" }.joined(separator: "\n")] }
    return Self(message: sections.joined(separator: "\n"),
      historySummary: "화면 분석 완료 · 앱 \(snapshot.activeApplication ?? "unknown")", succeeded: true)
  }
}
