import Foundation

struct MemoryRecord: Codable, Identifiable, Equatable {
  let id: UUID
  let type: MemoryType
  let key: String
  let value: String
  let source: String
  let confidence: Double
  let createdAt: Date
  let updatedAt: Date

  init(id: UUID = UUID(), type: MemoryType, key: String, value: String,
       source: String = "user", confidence: Double = 1, createdAt: Date = .now,
       updatedAt: Date = .now) {
    self.id = id
    self.type = type
    self.key = key
    self.value = value
    self.source = source
    self.confidence = confidence
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}

struct ActionHistoryValue: Codable, Equatable {
  let request: String
  let action: String
  let target: String
  let result: String
  let succeeded: Bool
  let timestamp: Date
}
