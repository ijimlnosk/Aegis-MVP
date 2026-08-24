struct ScreenInspectionResult: Equatable {
  let message: String
  let historySummary: String
  let succeeded: Bool

  static func format(snapshot: ScreenSnapshot, analysis: ScreenAnalysis,
                     projectContext: String?) -> Self {
    Self(message: ScreenAnalysisFormatter.format(snapshot: snapshot, analysis: analysis,
      projectContext: projectContext),
      historySummary: "화면 분석 완료 · 앱 \(snapshot.activeApplication ?? "unknown")", succeeded: true)
  }
}
