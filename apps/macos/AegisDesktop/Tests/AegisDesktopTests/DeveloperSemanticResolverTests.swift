import Foundation
import Testing
@testable import AegisDesktop

@Test func nPlusOneQuestionEntersSemanticDevelopmentRouting() throws {
  let root = try DeveloperTestSupport.gitProject()
  defer { try? FileManager.default.removeItem(at: root) }
  let repository = try DeveloperTestSupport.repositories(project: root).0
  #expect(DeveloperSemanticResolver.shouldClassify(
    "PTFriends에서 N+1 쿼리 문제가 발생할 수도 있는지 살펴봐", repository: repository))
}

@Test func semanticInvestigationMapsToReadOnlyCodingAnalysis() throws {
  let root = try DeveloperTestSupport.gitProject()
  defer { try? FileManager.default.removeItem(at: root) }
  let repository = try DeveloperTestSupport.repositories(project: root).0
  let project = ProjectEntity(name: "PTFriends", aliases: [], path: root.path)
  let decision = DeveloperSemanticDecision(intent: .investigateCode, confidence: 0.96)
  guard case .plan(let plan) = DeveloperSemanticResolver.resolve(decision,
    request: "N+1 가능성을 조사해", project: project, repository: repository) else {
    Issue.record("read-only investigation plan missing"); return
  }
  #expect(plan.steps.first?.action == .analyzeProjectWithCodingAgent)
  #expect(plan.steps.first?.codingMode == .readOnlyAnalysis)
  #expect(!plan.steps.first!.action.requiresApproval)
}

@Test func semanticMutationRequiresVeryHighConfidenceAndApproval() throws {
  let root = try DeveloperTestSupport.gitProject()
  defer { try? FileManager.default.removeItem(at: root) }
  let repository = try DeveloperTestSupport.repositories(project: root).0
  let project = ProjectEntity(name: "PTFriends", aliases: [], path: root.path)
  let uncertain = DeveloperSemanticDecision(intent: .modifyCode, confidence: 0.9)
  guard case .message = DeveloperSemanticResolver.resolve(uncertain, request: "고쳐",
    project: project, repository: repository) else { Issue.record("clarification missing"); return }
  let certain = DeveloperSemanticDecision(intent: .modifyCode, confidence: 0.98)
  guard case .plan(let plan) = DeveloperSemanticResolver.resolve(certain, request: "코드를 수정해",
    project: project, repository: repository) else { Issue.record("write plan missing"); return }
  #expect(plan.steps.first?.action == .executeCodingTask)
  #expect(ApprovalPolicy.requiresApproval(for: plan.steps.first!))
}
