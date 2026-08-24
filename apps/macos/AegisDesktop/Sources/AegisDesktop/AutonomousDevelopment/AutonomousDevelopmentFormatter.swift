enum AutonomousDevelopmentFormatter {
  static func proposal(_ candidate: DevelopmentTaskCandidate,
                       executable: Bool) -> String {
    var lines = ["\(candidate.projectName) 추천 작업", "", "문제:", candidate.title,
      "", "근거:"] + candidate.evidence.prefix(5).map { "- \($0)" }
    lines += ["", "예상 범위:", "\(candidate.estimatedChangedFiles)개 파일 이하",
      "", "검증:"] + candidate.validationStrategy.map { "- \($0.rawValue)" }
    lines += ["", "위험도:", candidate.overlapsExistingChanges ? "기존 변경과 겹침 · 검토 필요" : "낮음"]
    if !executable { lines += ["", "범위가 자율 실행 기준을 벗어나 제안만 표시합니다."] }
    return lines.joined(separator: "\n")
  }
}
