import Foundation

enum GitWorkflowFormatter {
  static func plan(_ plan: GitCommitPlan) -> String {
    var lines = ["\(plan.projectId) 커밋 계획", "", "Branch: \(plan.branch)", ""]
    for (index, group) in plan.groups.enumerated() {
      lines += ["\(index + 1). \(group.proposedMessage)", "   파일 \(group.files.count)개"]
      lines += group.files.map { "   - \($0)" }; lines.append("")
    }
    if !plan.unassignedFiles.isEmpty {
      lines += ["미분류 변경:"] + plan.unassignedFiles.map { "- \($0)" } + [""]
    }
    if !plan.warnings.isEmpty { lines += ["주의:"] + plan.warnings.map { "- \($0)" } + [""] }
    lines.append("예상 커밋: \(plan.groups.count)개")
    return lines.joined(separator: "\n")
  }

  static func execution(_ result: GitCommitExecutionResult, total: Int) -> String {
    var lines = ["커밋 결과"]
    lines += result.commits.enumerated().map { "- \($0.offset + 1)/\(total) \($0.element.sha) \($0.element.message)" }
    if let failed = result.failedGroup {
      lines.append("- \(result.commits.count + 1)/\(total) 실패: \(failed.proposedMessage)")
      if let reason = result.failureReason, !reason.isEmpty { lines.append("  원인: \(reason)") }
    }
    if result.commits.count + (result.failedGroup == nil ? 0 : 1) < total { lines.append("- 나머지 커밋은 실행하지 않았습니다.") }
    lines.append("push는 수행하지 않았습니다.")
    return lines.joined(separator: "\n")
  }

  static func push(_ proposal: GitPushProposal) -> String {
    """
    \(proposal.project) push

    Branch: \(proposal.branch)
    Remote: \(proposal.remote)
    Ahead: \(proposal.commitsAhead) commits
    Behind: \(proposal.commitsBehind)
    Action: \(proposal.upstream)으로 push
    """
  }

  static func status(project: String, snapshot: GitWorkingTreeSnapshot,
                     context: GitWorkflowContext) -> String {
    """
    Git 작업 상태
    - project: \(project)
    - branch: \(snapshot.branch)
    - working tree: \(snapshot.changedFiles.count) changes
    - commit plan: \(context.plan == nil ? "none" : context.state.rawValue)
    - pending commits: \(context.plan?.groups.count ?? 0)
    - push: \(context.pushProposal == nil ? "not requested" : "proposed")
    - CI: unavailable
    """
  }
}
