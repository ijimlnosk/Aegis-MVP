import Foundation

struct DevelopmentSession: Codable, Identifiable, Equatable {
  let id: UUID
  let project: String
  let startedAt: Date
  var endedAt: Date?
  let startingBranch: String
  let startingGitState: ProjectGitSnapshot
  var actions: [String]
  var endingGitState: ProjectGitSnapshot?
  var summary: String?

  init(id: UUID = UUID(), project: String, startedAt: Date = .now,
       startingGitState: ProjectGitSnapshot, actions: [String] = []) {
    self.id = id; self.project = project; self.startedAt = startedAt
    self.startingBranch = startingGitState.branch; self.startingGitState = startingGitState
    self.actions = actions
  }
}
