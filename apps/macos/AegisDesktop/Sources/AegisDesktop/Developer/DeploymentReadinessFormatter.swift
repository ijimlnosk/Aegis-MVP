enum DeploymentReadinessFormatter {
  static func format(project: String, readiness: DeploymentReadiness) -> String {
    var sections = ["\(project) 배포 준비 상태: \(readiness.state.rawValue.uppercased())"]
    append("통과", readiness.passed, to: &sections)
    append("주의", readiness.warnings, to: &sections)
    append("미지원", readiness.unsupported, to: &sections)
    append("차단", readiness.blockers, to: &sections)
    return sections.joined(separator: "\n\n")
  }

  private static func append(_ title: String, _ values: [String], to sections: inout [String]) {
    guard !values.isEmpty else { return }
    sections.append(title + ":\n" + values.map { "- \($0)" }.joined(separator: "\n"))
  }
}
