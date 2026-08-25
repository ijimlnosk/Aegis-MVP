import Foundation
import Testing
@testable import AegisDesktop

@Test func semanticGitClassifierRunsOnlyForBoundedWorkflowFollowUps() {
  var context = GitWorkflowContext(sessionId: "S1")
  #expect(!GitWorkflowSemanticResolver.shouldClassify("다시 짜줘", context: context))
  context.retain(semanticPlan())
  #expect(GitWorkflowSemanticResolver.shouldClassify("변경됐으니 계획 갱신해", context: context))
  #expect(!GitWorkflowSemanticResolver.shouldClassify("오늘 날씨가 어때?", context: context))
}

@Test func highConfidenceRebuildMapsToExistingTypedPlanner() throws {
  let root = try DeveloperTestSupport.gitProject(); defer { try? FileManager.default.removeItem(at: root) }
  let repository = try DeveloperTestSupport.repositories(project: root).0
  var context = GitWorkflowContext(sessionId: "S1"); context.retain(semanticPlan())
  let decision = GitFollowUpDecision(intent: .rebuildCommitPlan, confidence: 0.95)
  guard case .plan(let plan) = GitWorkflowSemanticResolver.resolve(decision,
    request: "변경됐으니 계획을 재구성해", repository: repository, context: &context) else {
    Issue.record("typed rebuild plan missing"); return
  }
  #expect(plan.steps.map(\.action) == [.proposeCommitPlan])
  #expect(plan.steps.first?.content?.contains("새 계획") == true)
}

@Test func uncertainOrInvalidatedExecutionNeverCommits() throws {
  let root = try DeveloperTestSupport.gitProject(); defer { try? FileManager.default.removeItem(at: root) }
  let repository = try DeveloperTestSupport.repositories(project: root).0
  var context = GitWorkflowContext(sessionId: "S1"); context.retain(semanticPlan())
  let uncertain = GitFollowUpDecision(intent: .executeCommitPlan, confidence: 0.7)
  guard case .message = GitWorkflowSemanticResolver.resolve(uncertain, request: "그거 해",
    repository: repository, context: &context) else { Issue.record("clarification missing"); return }
  context.state = .invalidated
  let certain = GitFollowUpDecision(intent: .executeCommitPlan, confidence: 0.99)
  guard case .message(let message) = GitWorkflowSemanticResolver.resolve(certain, request: "그거 실행해",
    repository: repository, context: &context) else { Issue.record("stale guard missing"); return }
  #expect(message.contains("새 계획"))
}

private func semanticPlan() -> GitCommitPlan {
  let entry = GitWorkingTreeEntry(path: "src/a.ts", originalPath: nil, indexStatus: " ",
    workTreeStatus: "M", kind: .modified, contentFingerprint: "src/a.ts")
  let snapshot = GitWorkingTreeSnapshot(head: "abc", branch: "main", entries: [entry],
    unstagedChanges: [], stagedChanges: [], trackedFiles: ["src/a.ts"])
  return GitCommitPlan(projectId: "PTFriends", branch: "main",
    baseSnapshot: snapshot, groups: [
      GitCommitGroup(title: "one", rationale: "one", files: ["src/a.ts"],
        proposedMessage: "fix: one", confidence: 1)], unassignedFiles: [], warnings: [])
}
