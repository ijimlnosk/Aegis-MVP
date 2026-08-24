import Foundation

enum DevelopmentTaskCategory: String, Codable, Sendable, CaseIterable {
  case bug, testFailure, typeError, lintIssue, deadCode, smallRefactor
  case architectureIssue, developerExperience, reliabilityIssue, performanceIssue
}

enum DevelopmentTaskSeverity: String, Codable, Sendable { case critical, high, medium, low }
enum DevelopmentTaskScope: String, Codable, Sendable { case tiny, small, medium, large }
enum ValidationAvailability: String, Codable, Sendable { case strong, moderate, weak, none }

struct DevelopmentTaskCandidate: Identifiable, Codable, Sendable, Equatable {
  let id: UUID
  let projectId: String
  let projectName: String
  let category: DevelopmentTaskCategory
  let title: String
  let summary: String
  let evidence: [String]
  let confidence: Double
  let severity: DevelopmentTaskSeverity
  let estimatedScope: DevelopmentTaskScope
  let estimatedChangedFiles: Int
  let validationStrategy: [ProjectValidationCheck]
  let validationAvailability: ValidationAvailability
  let proposedAt: Date
  let overlapsExistingChanges: Bool

  var fingerprint: String {
    ([projectId, category.rawValue, title.lowercased()] + evidence.sorted())
      .joined(separator: "|").lowercased()
  }
}
