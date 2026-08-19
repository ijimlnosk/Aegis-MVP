import Foundation

struct LearnedSkill: Codable, Identifiable, Equatable {
  let id: UUID
  var name: String
  var aliases: [String]
  var description: String
  var steps: [AgentStep]
  var confidence: Double
  var usageCount: Int
  let createdAt: Date
  var updatedAt: Date

  init(id: UUID = UUID(), name: String, aliases: [String] = [], description: String,
       steps: [AgentStep], confidence: Double = 0.7, usageCount: Int = 0,
       createdAt: Date = .now, updatedAt: Date = .now) {
    self.id = id; self.name = name; self.aliases = aliases; self.description = description
    self.steps = steps; self.confidence = confidence; self.usageCount = usageCount
    self.createdAt = createdAt; self.updatedAt = updatedAt
  }
}

struct SkillUsage: Codable, Equatable {
  let skillID: UUID
  let request: String
  let succeeded: Bool
  let createdAt: Date
}
