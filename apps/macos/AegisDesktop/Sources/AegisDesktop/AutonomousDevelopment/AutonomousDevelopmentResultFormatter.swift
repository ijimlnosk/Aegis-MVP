enum AutonomousDevelopmentResultFormatter {
  static func format(_ result: AutonomousDevelopmentResult) -> String {
    let success = [.succeeded, .succeededWithWarnings].contains(result.status)
    var lines = ["\(result.candidate.projectName) 작업 \(success ? "완료" : "미완료")", "",
      "선택한 작업:", result.candidate.title]
    if !result.changedFiles.isEmpty { lines += ["", "변경:"] + result.changedFiles.map { "- \($0)" } }
    if !result.validation.isEmpty {
      lines += ["", "검증:"] + result.validation.map { "- \($0.check.rawValue): \($0.status.rawValue)" }
    }
    lines += ["", "Repair:", result.repairAttempted ? "1회 사용" : "사용하지 않음",
      "", "기존 미커밋 변경:", "\(result.preexistingCount)건 유지"]
    if result.status == .needsReview { lines += ["", "변경 범위가 제한을 넘어 추가 자동 작업을 중단했습니다."] }
    if result.status == .repairFailed { lines += ["", "1회 복구 후에도 검증이 실패해 추가 시도하지 않았습니다."] }
    return lines.joined(separator: "\n")
  }
}
