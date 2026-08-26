import Foundation
import Testing
@testable import AegisDesktop

@Test func semanticRouterSelectsDeveloperRequestsThroughOneEntryPoint() throws {
  let root = try DeveloperTestSupport.gitProject()
  defer { try? FileManager.default.removeItem(at: root) }
  let repository = try DeveloperTestSupport.repositories(project: root).0

  let candidate = SemanticRouter.candidate(
    for: "PTFriends N+1 쿼리 가능성 조사해줘",
    repository: repository, gitContext: GitWorkflowContext())

  #expect(candidate?.kind == .developer)
}

@Test func semanticRouterIgnoresOrdinaryUnrelatedRequests() throws {
  let root = try DeveloperTestSupport.gitProject()
  defer { try? FileManager.default.removeItem(at: root) }
  let repository = try DeveloperTestSupport.repositories(project: root).0

  let candidate = SemanticRouter.candidate(for: "안녕",
    repository: repository, gitContext: GitWorkflowContext())

  #expect(candidate == nil)
}

@Test func semanticRouterNormalizesValidationAndCodingFollowUps() {
  let lint = SemanticRouter.followUp(
    for: "PTFriends lint 경고가 각각 어디서 나와?", hasCodingFindings: false)
  #expect(lint == .init(kind: .detailedLint, risk: .readOnly, requiresApproval: false))
  let freshLint = SemanticRouter.followUp(
    for: "PTFriends lint 경고 하나 찾아봐", hasCodingFindings: false)
  #expect(freshLint == .init(kind: .detailedLint, risk: .readOnly, requiresApproval: false))

  let fix = SemanticRouter.followUp(
    for: "수정 가능한 경고는 수정하자", hasCodingFindings: false)
  #expect(fix == .init(kind: .fixValidation, risk: .mutation, requiresApproval: true))

  let continuation = SemanticRouter.followUp(for: "그 부분 수정하자", hasCodingFindings: true)
  #expect(continuation == .init(
    kind: .codingContinuation, risk: .mutation, requiresApproval: true))
}

@Test func semanticRouterDoesNotInventCodingContext() {
  #expect(SemanticRouter.followUp(for: "그 부분 수정하자",
    hasCodingFindings: false) == nil)
}
