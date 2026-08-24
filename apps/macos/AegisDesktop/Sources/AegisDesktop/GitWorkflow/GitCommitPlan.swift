import Foundation

enum GitCommitPlanState: String, Codable {
  case none, proposed, awaitingCommitApproval, committing, committed
  case awaitingPushApproval, pushing, complete, cancelled, invalidated, expired, failed
}

struct GitCommitGroup: Codable, Equatable, Identifiable {
  let id: UUID
  let title: String
  let rationale: String
  let files: [String]
  let proposedMessage: String
  let confidence: Double
  let validationEvidence: [String]

  init(id: UUID = UUID(), title: String, rationale: String, files: [String],
       proposedMessage: String, confidence: Double, validationEvidence: [String] = []) {
    self.id = id; self.title = title; self.rationale = rationale; self.files = files.sorted()
    self.proposedMessage = proposedMessage; self.confidence = confidence
    self.validationEvidence = validationEvidence
  }
}

struct GitCommitPlan: Codable, Equatable, Identifiable {
  let id: UUID
  let projectId: String
  let branch: String
  let baseSnapshot: GitWorkingTreeSnapshot
  let groups: [GitCommitGroup]
  let unassignedFiles: [String]
  let warnings: [String]
  let createdAt: Date

  init(id: UUID = UUID(), projectId: String, branch: String, baseSnapshot: GitWorkingTreeSnapshot,
       groups: [GitCommitGroup], unassignedFiles: [String], warnings: [String], createdAt: Date = .now) {
    self.id = id; self.projectId = projectId; self.branch = branch; self.baseSnapshot = baseSnapshot
    self.groups = groups; self.unassignedFiles = unassignedFiles.sorted(); self.warnings = warnings
    self.createdAt = createdAt
  }
}

struct GitWorkflowContext {
  static let lifetime: TimeInterval = 45 * 60
  var sessionId: String = "desktop"
  var plan: GitCommitPlan?
  var state: GitCommitPlanState = .none
  var selectedGroupIds: Set<UUID> = []
  var createdCommits: [GitCreatedCommit] = []
  var pushProposal: GitPushProposal?
  var lastValidationReport: ProjectValidationReport?
  var createdAt: Date = .now
  var updatedAt: Date = .now
  var expiresAt: Date = Date().addingTimeInterval(lifetime)

  var activeCommitPlanId: UUID? { plan?.id }
  mutating func retain(_ plan: GitCommitPlan, now: Date = .now) {
    self.plan = plan; state = .proposed; selectedGroupIds = Set(plan.groups.map(\.id))
    lastValidationReport = nil
    updatedAt = now; expiresAt = now.addingTimeInterval(Self.lifetime)
  }
  mutating func expireIfNeeded(now: Date = .now) -> Bool {
    guard plan != nil, now >= expiresAt else { return false }
    state = .expired; return true
  }
  var canContinueCommit: Bool { [.proposed, .awaitingCommitApproval].contains(state) && plan != nil }
}

struct GitCreatedCommit: Codable, Equatable { let sha: String; let message: String; let files: [String] }
