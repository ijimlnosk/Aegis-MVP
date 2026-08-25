enum SemanticRouteKind: Equatable {
  case detailedLint
  case fixValidation
  case explainValidation
  case codingContinuation
  case developer
  case gitWorkflow
}

enum SemanticRisk: Equatable {
  case readOnly
  case mutation
}

struct SemanticIntentEnvelope: Equatable {
  let kind: SemanticRouteKind
  let risk: SemanticRisk
  let requiresApproval: Bool
}

enum SemanticRouteCandidate {
  case developer(ProjectEntity)
  case gitWorkflow

  var kind: SemanticRouteKind {
    switch self {
    case .developer: .developer
    case .gitWorkflow: .gitWorkflow
    }
  }
}

enum SemanticRouteDecision {
  case developer(ProjectEntity, DeveloperSemanticDecision)
  case gitWorkflow(GitFollowUpDecision)
}

enum SemanticRouter {
  static func followUp(for request: String, hasCodingFindings: Bool) -> SemanticIntentEnvelope? {
    if CodingResultFollowUpResolver.isDetailedLintQuestion(request) {
      return .init(kind: .detailedLint, risk: .readOnly, requiresApproval: false)
    }
    if CodingResultFollowUpResolver.isValidationFixRequest(request) {
      return .init(kind: .fixValidation, risk: .mutation, requiresApproval: true)
    }
    if CodingResultFollowUpResolver.isValidationQuestion(request) {
      return .init(kind: .explainValidation, risk: .readOnly, requiresApproval: false)
    }
    if hasCodingFindings && CodingContinuationIntentResolver.isPotentialFollowUp(request) {
      return .init(kind: .codingContinuation,
        risk: CodingContinuationIntentResolver.requestsMutation(request) ? .mutation : .readOnly,
        requiresApproval: CodingContinuationIntentResolver.requestsMutation(request))
    }
    return nil
  }

  static func candidate(for request: String, repository: MemoryRepository,
                        gitContext: GitWorkflowContext) -> SemanticRouteCandidate? {
    if DeveloperSemanticResolver.shouldClassify(request, repository: repository),
      let project = ProjectEntityResolver.resolve(in: request, repository: repository) {
      return .developer(project)
    }
    if GitWorkflowSemanticResolver.shouldClassify(request, context: gitContext) {
      return .gitWorkflow
    }
    return nil
  }

  static func classify(_ request: String, candidate: SemanticRouteCandidate,
                       gitContext: GitWorkflowContext) async throws -> SemanticRouteDecision {
    switch candidate {
    case .developer(let project):
      return .developer(project,
        try await DeveloperSemanticResolver.classify(request, project: project))
    case .gitWorkflow:
      return .gitWorkflow(
        try await GitWorkflowSemanticResolver.classify(request, context: gitContext))
    }
  }

  static func failureMessage(for candidate: SemanticRouteCandidate) -> String {
    switch candidate {
    case .developer: "개발 요청을 분류하지 못했습니다. 코드 조사인지 실제 수정인지 다시 말씀해 주세요."
    case .gitWorkflow: "커밋 후속 요청을 분류하지 못했습니다. 계획을 다시 만들지, 실행할지 말씀해 주세요."
    }
  }
}
