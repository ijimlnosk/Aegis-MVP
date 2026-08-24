import Foundation

enum GitCommitPlanEditor {
  static func update(_ plan: GitCommitPlan, request: String) throws -> GitCommitPlan {
    let text = request.lowercased()
    var groups = plan.groups
    var unassigned = plan.unassignedFiles
    let numbered = groups.indices.filter { mentions(index: $0, in: text) }
    let excludedIndexes = groups.indices.filter { index in
      mentions(index: index, in: text) && ["빼", "제외"].contains(where: text.contains)
    }
    if !excludedIndexes.isEmpty {
      unassigned += excludedIndexes.flatMap { groups[$0].files }
      groups = groups.enumerated().filter { !excludedIndexes.contains($0.offset) }.map(\.element)
    } else if !numbered.isEmpty && (text.contains("만") || text.contains("진행") || text.contains(" 해")) {
      groups = numbered.map { groups[$0] }
    }
    if ["빼", "제외", "건드리지 마"].contains(where: text.contains) {
      groups = groups.compactMap { group in
        if semanticallyExcluded(group, by: text) {
          unassigned += group.files; return nil
        }
        let kept = group.files.filter { path in
          !text.contains(path.lowercased())
            && !text.contains(URL(fileURLWithPath: path).lastPathComponent.lowercased())
        }
        unassigned += group.files.filter { !kept.contains($0) }
        return kept.isEmpty ? nil : GitCommitGroup(id: group.id, title: group.title,
          rationale: group.rationale, files: kept, proposedMessage: group.proposedMessage,
          confidence: group.confidence, validationEvidence: group.validationEvidence)
      }
    }
    let updated = GitCommitPlan(projectId: plan.projectId, branch: plan.branch,
      baseSnapshot: plan.baseSnapshot, groups: groups, unassignedFiles: Array(Set(unassigned)),
      warnings: plan.warnings)
    try GitCommitPolicy.validate(updated); return updated
  }

  private static func mentions(index: Int, in text: String) -> Bool {
    let number = index + 1
    return text.contains("\(number)번") || (number == 1 && text.contains("첫 번째"))
      || (number == 2 && text.contains("두 번째")) || (number == 3 && text.contains("세 번째"))
  }

  private static func semanticallyExcluded(_ group: GitCommitGroup, by text: String) -> Bool {
    let keys = group.files.flatMap { path in
      let parts = path.lowercased().split(separator: "/").map(String.init)
      return Array(parts.prefix(2))
    }
    return keys.contains(where: { $0.count >= 3 && text.contains($0) })
  }
}
