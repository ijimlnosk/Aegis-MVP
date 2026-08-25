import Foundation
import Testing
@testable import AegisDesktop

private func gitEntry(_ path: String, index: String = " ", worktree: String = "M") -> GitWorkingTreeEntry {
  .init(path: path, originalPath: nil, indexStatus: index, workTreeStatus: worktree,
    kind: index == "?" ? .untracked : .modified, contentFingerprint: path)
}

private func gitSnapshot(_ paths: [String], branch: String = "dev",
                         staged: Bool = false) -> GitWorkingTreeSnapshot {
  let entries = paths.map { gitEntry($0, index: staged ? "M" : ($0.hasPrefix("new/") ? "?" : " ")) }
  return .init(head: "abc", branch: branch, entries: entries, unstagedChanges: [],
    stagedChanges: staged ? [.init(status: "M", path: paths[0], originalPath: nil)] : [],
    trackedFiles: paths)
}

@Test func commitPlanGroupsRelatedFilesAndLeavesUnknownUnassigned() throws {
  let root = URL(fileURLWithPath: "/tmp")
  let snapshot = gitSnapshot(["views/records/useMealLogMutations.ts",
    "views/records/mealLogRequestLog.ts", "__tests__/mealLogRequestLog.test.ts",
    "shared/assets/sample/image.txt"])
  let plan = try GitCommitPlanner.create(project: "PTFriends", root: root,
    snapshot: snapshot, request: "나눠서 커밋하자")
  #expect(plan.groups.count == 1)
  #expect(plan.groups[0].files.count == 3)
  #expect(plan.unassignedFiles == ["shared/assets/sample/image.txt"])
}

@Test func commitPlanLeavesTrackedBuildArtifactsUnassigned() throws {
  let root = try DeveloperTestSupport.gitProject(); defer { try? FileManager.default.removeItem(at: root) }
  let build = root.appendingPathComponent("apps/macos/AegisDesktop/.build/release")
  try FileManager.default.createDirectory(at: build, withIntermediateDirectories: true)
  try "lock".write(to: root.appendingPathComponent("apps/macos/AegisDesktop/.build/.lock"), atomically: true, encoding: .utf8)
  let source = root.appendingPathComponent("apps/macos/AegisDesktop/Sources/AegisDesktop.swift")
  try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
  try "changed".write(to: source, atomically: true, encoding: .utf8)
  let snapshot = gitSnapshot(["apps/macos/AegisDesktop/.build/.lock",
    "apps/macos/AegisDesktop/.build/release", "apps/macos/AegisDesktop/Sources/AegisDesktop.swift"])
  let plan = try GitCommitPlanner.create(project: "PTFriends", root: root, snapshot: snapshot,
    request: "변경사항 나눠서 커밋하자")
  #expect(plan.groups.flatMap { $0.files }.contains("apps/macos/AegisDesktop/.build/.lock") == false)
  #expect(plan.unassignedFiles.contains("apps/macos/AegisDesktop/.build/.lock"))
}

@Test func sensitiveFilesAreNeverAutomaticallyGrouped() throws {
  let plan = try GitCommitPlanner.create(project: "PTFriends", root: URL(fileURLWithPath: "/tmp"),
    snapshot: gitSnapshot(["config/.env.local", "src/feature.ts"]), request: "커밋하자")
  #expect(plan.unassignedFiles.contains("config/.env.local"))
  #expect(!plan.groups.flatMap(\.files).contains("config/.env.local"))
}

@Test func manySmallGroupsMaySumPastMaximumFilesAsLongAsEachGroupStaysWithinTheCap() throws {
  let paths = (0..<90).map { "src/group\($0 / 30)/file\($0).ts" }
  let snapshot = gitSnapshot(paths)
  let groups = (0..<3).map { index in
    GitCommitGroup(title: "group\(index)", rationale: "r", files: (0..<30).map { "src/group\(index)/file\(index * 30 + $0).ts" },
      proposedMessage: "chore: group\(index)", confidence: 1)
  }
  let plan = GitCommitPlan(projectId: "PTFriends", branch: "dev", baseSnapshot: snapshot,
    groups: groups, unassignedFiles: [], warnings: [])
  #expect(throws: Never.self) { try GitCommitPolicy.validate(plan) }
}

@Test func aSingleGroupOverTheMaximumFileCapIsStillRejected() {
  let paths = (0..<51).map { "src/file\($0).ts" }
  let snapshot = gitSnapshot(paths)
  let group = GitCommitGroup(title: "one", rationale: "r", files: paths, proposedMessage: "chore: one", confidence: 1)
  let plan = GitCommitPlan(projectId: "PTFriends", branch: "dev", baseSnapshot: snapshot,
    groups: [group], unassignedFiles: [], warnings: [])
  #expect(throws: GitWorkflowError.self) { try GitCommitPolicy.validate(plan) }
}

@Test func commitPlannerSplitsADeepMonorepoTreeByContainingDirectoryNotByTopLevelPrefix() throws {
  let root = URL(fileURLWithPath: "/tmp")
  let snapshot = gitSnapshot(["apps/macos/AegisDesktop/Sources/AegisDesktop/Developer/DeveloperIntentResolver.swift",
    "apps/macos/AegisDesktop/Sources/AegisDesktop/Screen/ScreenAnalysis.swift"])
  let plan = try GitCommitPlanner.create(project: "Aegis-MVP", root: root, snapshot: snapshot, request: "나눠서 커밋하자")
  #expect(plan.groups.count == 2)
}

@Test func duplicateCommitGroupFilesAreRejected() {
  let snapshot = gitSnapshot(["src/a.ts"])
  let group = GitCommitGroup(title: "one", rationale: "one", files: ["src/a.ts"],
    proposedMessage: "fix: one", confidence: 1)
  let plan = GitCommitPlan(projectId: "PTFriends", branch: "dev", baseSnapshot: snapshot,
    groups: [group, group], unassignedFiles: [], warnings: [])
  #expect(throws: GitWorkflowError.self) { try GitCommitPolicy.validate(plan) }
}

@Test func gitMutationApprovalBoundariesAreSeparate() {
  #expect(!ApprovalPolicy.requiresApproval(for: .proposeCommitPlan))
  #expect(ApprovalPolicy.risk(for: .createCommit) == .localMutation)
  #expect(ApprovalPolicy.risk(for: .pushCurrentBranch) == .remoteMutation)
  #expect(ApprovalPolicy.requiresApproval(for: .createCommit))
  #expect(ApprovalPolicy.requiresApproval(for: .pushCurrentBranch))
}

@Test func commitAndPushIntentCreatesTwoApprovalBoundaries() throws {
  let root = try DeveloperTestSupport.gitProject(); defer { try? FileManager.default.removeItem(at: root) }
  let repository = try DeveloperTestSupport.repositories(project: root).0
  let plan = GitWorkflowIntentResolver.plan(for: "PTFriends 커밋하고 푸시하자",
    repository: repository, context: .init())!
  #expect(plan.steps.map(\.action) == [.proposeCommitPlan, .createCommit, .proposePush, .pushCurrentBranch])
  #expect(plan.steps[0].dependency == .independent)
  #expect(plan.steps.dropFirst().allSatisfy { $0.dependency == .requiresPreviousSuccess })
  #expect(plan.steps.filter { ApprovalPolicy.requiresApproval(for: $0) }.count == 2)
}

@Test func proposalOnlyIntentNeverStagesOrRequestsApproval() throws {
  let root = try DeveloperTestSupport.gitProject(); defer { try? FileManager.default.removeItem(at: root) }
  let repository = try DeveloperTestSupport.repositories(project: root).0
  let plan = GitWorkflowIntentResolver.plan(for: "PTFriends 현재 변경사항 커밋 단위로 정리해줘",
    repository: repository, context: .init())!
  #expect(plan.steps.map(\.action) == [.proposeCommitPlan])
  #expect(!ApprovalPolicy.requiresApproval(for: plan.steps[0]))
}

@Test func protectedBranchAndForbiddenGitSurfacesAreClosed() {
  #expect(GitPushPolicy.protectedBranches.contains("main"))
  #expect(AgentAction(rawValue: "run_git_command") == nil)
  #expect(AgentAction(rawValue: "merge_pull_request") == nil)
  #expect(AgentAction(rawValue: "force_push") == nil)
}

@Test func approvedCommitStagesAndCommitsOnlyExactPlannedFiles() throws {
  let root = try DeveloperTestSupport.gitProject(); defer { try? FileManager.default.removeItem(at: root) }
  _ = try DeveloperTestSupport.process("/usr/bin/git", ["config", "user.name", "Aegis"], at: root)
  _ = try DeveloperTestSupport.process("/usr/bin/git", ["config", "user.email", "aegis@example.test"], at: root)
  try "changed\n".write(to: root.appending(path: "README.md"), atomically: true, encoding: .utf8)
  try "manual\n".write(to: root.appending(path: "manual.txt"), atomically: true, encoding: .utf8)
  let snapshot = try CodingGitInspector.snapshot(at: root)
  let group = GitCommitGroup(title: "docs", rationale: "bounded", files: ["README.md"],
    proposedMessage: "docs: update readme", confidence: 1)
  let plan = GitCommitPlan(projectId: "PTFriends", branch: snapshot.branch,
    baseSnapshot: snapshot, groups: [group], unassignedFiles: ["manual.txt"], warnings: [])
  let result = try GitCommitExecutor.execute(plan, root: root, validate: {
    ProjectValidationReport.documentationOnly(project: "PTFriends")
  })
  #expect(result.succeeded)
  #expect(result.commits.first?.files == ["README.md"])
  let after = try CodingGitInspector.snapshot(at: root)
  #expect(after.changedFiles == ["manual.txt"])
}

@Test func stagedAndStalePlansFailBeforeCommit() throws {
  let root = try DeveloperTestSupport.gitProject(); defer { try? FileManager.default.removeItem(at: root) }
  try "changed\n".write(to: root.appending(path: "README.md"), atomically: true, encoding: .utf8)
  let base = try CodingGitInspector.snapshot(at: root)
  let group = GitCommitGroup(title: "docs", rationale: "bounded", files: ["README.md"],
    proposedMessage: "docs: update readme", confidence: 1)
  let plan = GitCommitPlan(projectId: "PTFriends", branch: base.branch, baseSnapshot: base,
    groups: [group], unassignedFiles: [], warnings: [])
  try "changed again\n".write(to: root.appending(path: "README.md"), atomically: true, encoding: .utf8)
  #expect(throws: GitWorkflowError.self) { try GitCommitExecutor.execute(plan, root: root, validate: {
    ProjectValidationReport.documentationOnly(project: "PTFriends")
  }) }

  _ = try DeveloperTestSupport.process("/usr/bin/git", ["add", "--", "README.md"], at: root)
  let staged = try CodingGitInspector.snapshot(at: root)
  let stagedPlan = GitCommitPlan(projectId: "PTFriends", branch: staged.branch,
    baseSnapshot: staged, groups: [group], unassignedFiles: [], warnings: [])
  #expect(throws: GitWorkflowError.self) { try GitCommitExecutor.execute(stagedPlan, root: root, validate: {
    ProjectValidationReport.documentationOnly(project: "PTFriends")
  }) }
}

@Test func conversationalPlanSelectionKeepsOnlyExplicitGroups() throws {
  let snapshot = gitSnapshot(["src/a.ts", "docs/readme.md"])
  let groups = [
    GitCommitGroup(title: "one", rationale: "one", files: ["src/a.ts"],
      proposedMessage: "fix: first", confidence: 1),
    GitCommitGroup(title: "two", rationale: "two", files: ["docs/readme.md"],
      proposedMessage: "docs: second", confidence: 1)]
  let plan = GitCommitPlan(projectId: "PTFriends", branch: "dev", baseSnapshot: snapshot,
    groups: groups, unassignedFiles: [], warnings: [])
  let updated = try GitCommitPlanEditor.update(plan, request: "첫 번째만 해")
  #expect(updated.groups.count == 1)
  #expect(updated.groups[0].files == ["src/a.ts"])
  #expect(updated.id != plan.id)
}

@Test func proposedPlanPersistsAndContinuationAwaitsApproval() throws {
  let root = try DeveloperTestSupport.gitProject(); defer { try? FileManager.default.removeItem(at: root) }
  let repository = try DeveloperTestSupport.repositories(project: root).0
  let plan = GitCommitPlan(projectId: "PTFriends", branch: "main",
    baseSnapshot: gitSnapshot(["src/a.ts"], branch: "main"), groups: [
      GitCommitGroup(title: "one", rationale: "one", files: ["src/a.ts"],
        proposedMessage: "fix: first", confidence: 1)], unassignedFiles: [], warnings: [])
  var context = GitWorkflowContext(sessionId: "S1"); context.retain(plan)
  let continuation = GitWorkflowContinuationResolver.resolve("커밋 진행해",
    repository: repository, context: &context)
  guard case .plan(let execution) = continuation else { Issue.record("continuation missing"); return }
  #expect(context.activeCommitPlanId == plan.id)
  #expect(execution.steps.map(\.action) == [.proposeCommitPlan, .createCommit])
  var executor = try AgentPlanExecutor(plan: execution, request: "커밋 진행해")
  guard case .execute(let prepare, _, _) = executor.next() else { Issue.record("prepare missing"); return }
  let completed = executor.complete(prepare.id, succeeded: true); #expect(completed)
  guard case .approval(let commit, _, _) = executor.next() else { Issue.record("approval missing"); return }
  #expect(commit.action == .createCommit)
  #expect(executor.state.executionState == .pausedForApproval)
}

@Test func vagueContinuationsAreDeterministicAndNoPlanIsTyped() throws {
  let root = try DeveloperTestSupport.gitProject(); defer { try? FileManager.default.removeItem(at: root) }
  let repository = try DeveloperTestSupport.repositories(project: root).0
  for phrase in ["진행해", "커밋 진행해", "좋아 해", "전부 진행해", "해"] {
    var empty = GitWorkflowContext(sessionId: "S1")
    guard case .message(let message) = GitWorkflowContinuationResolver.resolve(phrase,
      repository: repository, context: &empty) else { Issue.record("typed error missing: \(phrase)"); continue }
    #expect(message == "진행할 커밋 계획이 없습니다.")
    #expect(!message.contains("작업 상태를 확인하지 못했습니다"))
  }
}

@Test func stalePlanRebuildPhraseCreatesANewPlanWithoutUsingTheGeneralPlanner() throws {
  let root = try DeveloperTestSupport.gitProject(); defer { try? FileManager.default.removeItem(at: root) }
  let repository = try DeveloperTestSupport.repositories(project: root).0
  let snapshot = gitSnapshot(["src/a.ts"], branch: "main")
  let plan = GitCommitPlan(projectId: "PTFriends", branch: "main", baseSnapshot: snapshot,
    groups: [GitCommitGroup(title: "one", rationale: "one", files: ["src/a.ts"],
      proposedMessage: "fix: first", confidence: 1)], unassignedFiles: [], warnings: [])
  var context = GitWorkflowContext(sessionId: "S1"); context.retain(plan)
  context.state = .invalidated
  guard case .plan(let rebuilt) = GitWorkflowContinuationResolver.resolve("어 새로 만들어",
    repository: repository, context: &context) else { Issue.record("replan missing"); return }
  #expect(rebuilt.steps.map(\.action) == [.proposeCommitPlan])
  #expect(rebuilt.steps.first?.project == "PTFriends")
  #expect(rebuilt.steps.first?.content?.contains("새 계획") == true)
}

@Test func sessionsCannotAccessAnotherSessionsPlanAndCommandIdentityIsIrrelevant() throws {
  let root = try DeveloperTestSupport.gitProject(); defer { try? FileManager.default.removeItem(at: root) }
  let repository = try DeveloperTestSupport.repositories(project: root).0
  let plan = GitCommitPlan(projectId: "PTFriends", branch: "main",
    baseSnapshot: gitSnapshot(["src/a.ts"], branch: "main"), groups: [
      GitCommitGroup(title: "one", rationale: "one", files: ["src/a.ts"],
        proposedMessage: "fix: first", confidence: 1)], unassignedFiles: [], warnings: [])
  var sessionA = GitWorkflowContext(sessionId: "S1"); sessionA.retain(plan)
  var sessionB = GitWorkflowContext(sessionId: "S2")
  #expect(GitWorkflowContinuationResolver.resolve("진행해", repository: repository,
    context: &sessionA) != nil)
  guard case .message(let message) = GitWorkflowContinuationResolver.resolve("진행해",
    repository: repository, context: &sessionB) else { Issue.record("cross-session leak"); return }
  #expect(message == "진행할 커밋 계획이 없습니다.")
}

@Test func expiredAndCancelledPlansCannotResume() throws {
  let root = try DeveloperTestSupport.gitProject(); defer { try? FileManager.default.removeItem(at: root) }
  let repository = try DeveloperTestSupport.repositories(project: root).0
  let plan = GitCommitPlan(projectId: "PTFriends", branch: "main",
    baseSnapshot: gitSnapshot(["src/a.ts"], branch: "main"), groups: [
      GitCommitGroup(title: "one", rationale: "one", files: ["src/a.ts"],
        proposedMessage: "fix: first", confidence: 1)], unassignedFiles: [], warnings: [])
  var expired = GitWorkflowContext(sessionId: "S1"); expired.retain(plan, now: .distantPast)
  guard case .message(let expiry) = GitWorkflowContinuationResolver.resolve("진행해",
    repository: repository, context: &expired, now: .now) else { Issue.record("expiry missing"); return }
  #expect(expiry.contains("만료"))
  var cancelled = GitWorkflowContext(sessionId: "S1"); cancelled.retain(plan); cancelled.state = .cancelled
  guard case .message(let cancellation) = GitWorkflowContinuationResolver.resolve("진행해",
    repository: repository, context: &cancelled) else { Issue.record("cancellation missing"); return }
  #expect(cancellation.contains("취소"))
}

@Test func numberedAndSemanticExclusionsUpdateExistingPlan() throws {
  let snapshot = gitSnapshot(["src/a.ts", "docs/readme.md", "android/app/build.gradle"])
  let groups = [
    GitCommitGroup(title: "one", rationale: "one", files: ["src/a.ts"], proposedMessage: "fix: one", confidence: 1),
    GitCommitGroup(title: "two", rationale: "two", files: ["docs/readme.md"], proposedMessage: "docs: two", confidence: 1),
    GitCommitGroup(title: "android", rationale: "three", files: ["android/app/build.gradle"], proposedMessage: "chore: android", confidence: 1)]
  let plan = GitCommitPlan(projectId: "PTFriends", branch: "dev", baseSnapshot: snapshot,
    groups: groups, unassignedFiles: [], warnings: [])
  #expect(try GitCommitPlanEditor.update(plan, request: "1번이랑 2번 진행해").groups.count == 2)
  let withoutSecond = try GitCommitPlanEditor.update(plan, request: "2번은 빼")
  #expect(withoutSecond.groups.count == 2); #expect(withoutSecond.unassignedFiles.contains("docs/readme.md"))
  let withoutAndroid = try GitCommitPlanEditor.update(plan, request: "android 변경은 제외하고 진행해")
  #expect(!withoutAndroid.groups.flatMap(\.files).contains("android/app/build.gradle"))
}
