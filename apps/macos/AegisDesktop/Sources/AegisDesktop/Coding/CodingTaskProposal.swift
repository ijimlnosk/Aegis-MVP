import Foundation

enum CodingTaskProposalLifecycle: String, Sendable {
  case proposed, awaitingApproval, approved, running, providerFinished
  case verifying, succeeded, failed, rejected, cancelled
}

struct CodingTaskProposal: Identifiable, Sendable, Equatable {
  let id: UUID
  let sourceFindingId: UUID?
  let projectId: String
  let projectName: String
  let goal: String
  let currentRequest: String
  let evidence: [String]
  let intendedOutcome: String
  let validationProfile: [String]
  let mode: CodingTaskMode
  let provider: CodingAgentProviderID

  static func make(project: String, request: String, finding: CodingFindingContext?,
                   repository: MemoryRepository,
                   provider: CodingAgentProviderID? = nil) throws -> Self {
    let root = try ProjectCommandPolicy.projectURL(project, repository: repository)
    guard FileManager.default.fileExists(atPath: root.appending(path: ".git").path) else {
      throw CodingTaskError.notGitRepository
    }
    let matched = finding.flatMap { $0.projectId == project.lowercased() ? $0 : nil }
    return .init(id: UUID(), sourceFindingId: matched?.id,
      projectId: project.lowercased(), projectName: project,
      goal: String((matched?.title ?? request).prefix(500)), currentRequest: String(request.prefix(1_000)),
      evidence: matched.map { Array($0.evidenceLocations.prefix(8)) } ?? [],
      intendedOutcome: String((matched?.recommendation ?? request).prefix(800)),
      validationProfile: ["typecheck", "lint", "tests"], mode: .workspaceWrite,
      provider: provider ?? CodingAgentProviderResolver.resolve(request: request,
        project: project, repository: repository))
  }
}
