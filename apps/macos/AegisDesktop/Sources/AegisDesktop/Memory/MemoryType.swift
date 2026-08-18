enum MemoryType: String, Codable, CaseIterable {
  case fact
  case preference
  case alias
  case project
  case actionHistory = "action_history"
}
