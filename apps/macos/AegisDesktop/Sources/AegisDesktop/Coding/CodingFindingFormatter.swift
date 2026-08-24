enum CodingFindingFormatter {
  static func explain(_ finding: CodingFindingContext) -> String {
    var lines = [finding.title, "", finding.summary]
    if !finding.evidenceLocations.isEmpty {
      lines += ["", "관련 위치:"] + finding.evidenceLocations.map { "- \($0)" }
    }
    lines += ["", "권장:", finding.recommendation, "", "코드는 수정하지 않았습니다."]
    return lines.joined(separator: "\n")
  }
}
