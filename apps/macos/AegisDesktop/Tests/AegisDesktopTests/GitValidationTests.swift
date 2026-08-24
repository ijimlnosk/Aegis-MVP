import Foundation
import Testing
@testable import AegisDesktop

private func check(_ kind: ProjectValidationCheck, _ status: ValidationStatus,
                   warnings: Int = 0, summary: String = "result") -> ProjectValidationResult {
  .init(check: kind, status: status, summary: summary, warningCount: warnings,
    exitCode: status == .failed ? 1 : 0)
}

private func report(_ checks: [ProjectValidationResult],
                    required: [ProjectValidationCheck] = [.typecheck, .test]) -> ProjectValidationReport {
  .make(project: "PTFriends", profile: .init(requiredChecks: required,
    optionalChecks: ProjectValidationCheck.allCases.filter { !required.contains($0) }), checks: checks)
}

@Test func preCommitValidationAllowsPassWarningsAndUnsupportedOptionalBuild() {
  let value = report([check(.typecheck, .passed), check(.lint, .warning, warnings: 15),
    check(.test, .passed), check(.build, .unsupported)])
  #expect(value.overall == .passedWithWarnings)
  #expect(value.allowsCommit)
  #expect(value.checks.last?.supportStatus == .unsupported)
}

@Test func missingBuildScriptIsOptionalUnsupportedNotFailure() throws {
  let root = try DeveloperTestSupport.gitProject(); defer { try? FileManager.default.removeItem(at: root) }
  let packageJSON = #"{"scripts":{"typecheck":"tsc --noEmit","lint":"eslint .","test":"jest"}}"#
  try packageJSON.write(to: root.appending(path: "package.json"), atomically: true, encoding: .utf8)
  let repository = try DeveloperTestSupport.repositories(project: root).0
  let profile = ProjectValidationProfile.resolve(project: "PTFriends",
    package: try PackageScriptTool.inspect(at: root), repository: repository)
  #expect(profile.requiredChecks == [.typecheck, .test])
  #expect(profile.optionalChecks == [.lint])
  #expect(profile.unsupportedChecks == [.build])
}

@Test func requiredAndSupportedFailuresBlockCommitWhileRequiredUnavailableIsTyped() {
  for failed in [ProjectValidationCheck.typecheck, .lint, .test] {
    let value = report(ProjectValidationCheck.allCases.map {
      check($0, $0 == failed ? .failed : ($0 == .build ? .unsupported : .passed))
    })
    #expect(value.overall == .failed)
    #expect(!value.allowsCommit)
  }
  let unavailable = report([check(.typecheck, .skipped), check(.test, .passed),
    check(.lint, .passed), check(.build, .unsupported)])
  #expect(unavailable.overall == .unavailable)
  #expect(!unavailable.allowsCommit)
}

@Test func validationFailureFormattingIsBoundedAndShowsExactRemoteEvidence() {
  let value = report([check(.typecheck, .passed), check(.lint, .warning, warnings: 15),
    check(.test, .failed, summary: "__tests__/quickExerciseLog.test.ts:13\nExpected: true\nReceived: false"),
    check(.build, .unsupported)])
  let formatted = GitValidationFormatter.format(value, failedCommit: true)
  #expect(formatted.contains("test:\n실패 (exit 1)"))
  #expect(formatted.contains("quickExerciseLog.test.ts:13"))
  #expect(formatted.contains("lint:\n경고 15건"))
  #expect(formatted.contains("build:\n지원하지 않음"))
  #expect(formatted.contains("커밋은 생성하지 않았습니다."))
  #expect(formatted.count < 4_000)
}

@Test func sameSessionCanExplainLatestCommitValidationWithoutLLM() throws {
  let root = try DeveloperTestSupport.gitProject(); defer { try? FileManager.default.removeItem(at: root) }
  let repository = try DeveloperTestSupport.repositories(project: root).0
  var context = GitWorkflowContext(sessionId: "remote-S1")
  context.lastValidationReport = report([check(.typecheck, .passed), check(.lint, .warning),
    check(.test, .failed, summary: "quickExerciseLog.test.ts:13 failed"), check(.build, .unsupported)])
  guard case .message(let message) = GitWorkflowContinuationResolver.resolve(
    "방금 커밋 검증에서 뭐가 실패했어?", repository: repository, context: &context) else {
    Issue.record("typed validation follow-up missing"); return
  }
  #expect(message.contains("quickExerciseLog.test.ts:13"))
}

@Test func failedValidationCreatesNoCommitAndLeavesIndexUnchanged() throws {
  let root = try DeveloperTestSupport.gitProject(); defer { try? FileManager.default.removeItem(at: root) }
  try "changed\n".write(to: root.appending(path: "README.md"), atomically: true, encoding: .utf8)
  let snapshot = try CodingGitInspector.snapshot(at: root)
  let group = GitCommitGroup(title: "docs", rationale: "test", files: ["README.md"],
    proposedMessage: "docs: update readme", confidence: 1)
  let plan = GitCommitPlan(projectId: "PTFriends", branch: snapshot.branch,
    baseSnapshot: snapshot, groups: [group], unassignedFiles: [], warnings: [])
  let failed = report([check(.typecheck, .passed), check(.lint, .passed),
    check(.test, .failed), check(.build, .unsupported)])
  #expect(throws: GitWorkflowError.self) {
    try GitCommitExecutor.execute(plan, root: root, validate: { failed })
  }
  #expect(try CodingGitInspector.snapshot(at: root).stagedChanges.isEmpty)
}
