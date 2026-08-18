enum MemoryIntent: Equatable {
  case remember(type: MemoryType, key: String, value: String)
  case forget(type: MemoryType, key: String)
  case list(type: MemoryType?)
  case lookup(type: MemoryType, key: String)
}
