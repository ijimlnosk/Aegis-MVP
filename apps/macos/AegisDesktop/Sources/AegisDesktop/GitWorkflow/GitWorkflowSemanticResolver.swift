import Foundation

enum GitFollowUpIntent: String, Codable, CaseIterable {
  case rebuildCommitPlan = "rebuild_commit_plan"
  case executeCommitPlan = "execute_commit_plan"
  case explainFailure = "explain_failure"
  case cancelCommitPlan = "cancel_commit_plan"
  case unrelated
}

struct GitFollowUpDecision: Codable, Equatable {
  let intent: GitFollowUpIntent
  let confidence: Double
}

enum GitWorkflowSemanticResolver {
  static func shouldClassify(_ request: String, context: GitWorkflowContext) -> Bool {
    guard context.plan != nil, request.count <= 100 else { return false }
    let text = request.lowercased()
    return ["커밋", "계획", "다시", "새로", "갱신", "재구성", "짜", "만들",
      "진행", "실행", "취소", "왜", "오류", "그거", "그걸"]
      .contains(where: text.contains)
  }

  static func classify(_ request: String, context: GitWorkflowContext) async throws -> GitFollowUpDecision {
    let project = context.plan?.projectId ?? "unknown"
    let content = "request=\(request)\nactiveProject=\(project)\nworkflowState=\(context.state.rawValue)"
    return try await CodexPlanner(timeout: 45).structured(GitFollowUpDecision.self,
      system: "Classify the Korean follow-up using only an allowed intent. Never execute anything. Confidence must be 0...1.",
      content: content, schema: schema)
  }

  static func resolve(_ decision: GitFollowUpDecision, request: String,
                      repository: MemoryRepository,
                      context: inout GitWorkflowContext) -> GitWorkflowContinuation? {
    guard (0...1).contains(decision.confidence), decision.confidence >= 0.9 else {
      return .message("요청을 확실히 이해하지 못했습니다. 커밋 계획을 다시 만들지, 실행할지 말씀해 주세요.")
    }
    guard let project = context.plan?.projectId,
      ProjectEntityResolver.resolve(name: project, repository: repository) != nil else { return nil }
    switch decision.intent {
    case .rebuildCommitPlan:
      return .plan(AgentPlan(step: AgentStep(action: .proposeCommitPlan,
        content: "새 계획: \(request)", project: project)))
    case .executeCommitPlan:
      guard context.state != .invalidated else {
        return .message("변경사항이 달라져 기존 계획은 실행할 수 없습니다. 먼저 새 계획을 만들어 주세요.")
      }
      return GitWorkflowContinuationResolver.resolve("커밋 진행해", repository: repository,
        context: &context)
    case .explainFailure:
      guard let report = context.lastValidationReport else {
        return .message("최근 커밋 검증 결과가 없습니다.")
      }
      return .message(GitValidationFormatter.format(report, failedCommit: !report.allowsCommit))
    case .cancelCommitPlan:
      context.state = .cancelled
      return .message("현재 커밋 계획을 취소했습니다.")
    case .unrelated: return nil
    }
  }

  static let schema: [String: Any] = ["type": "object", "properties": [
    "intent": ["type": "string", "enum": GitFollowUpIntent.allCases.map(\.rawValue)],
    "confidence": ["type": "number", "minimum": 0, "maximum": 1]],
    "required": ["intent", "confidence"], "additionalProperties": false]
}
