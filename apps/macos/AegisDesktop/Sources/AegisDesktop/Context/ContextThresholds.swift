struct ContextThresholds: Equatable {
  var memoryWarning = 80.0
  var memoryCritical = 90.0
  var diskWarning = 80.0
  var diskCritical = 90.0
  var projectNoteworthy = 10
  var projectWarning = 30
  var projectOverrides: [String: Int] = [:]

  func applying(_ preferences: [MemoryRecord]) -> Self {
    var result = self
    for item in preferences where item.type == .preference {
      guard let value = Double(item.value.filter { $0.isNumber || $0 == "." }) else { continue }
      switch item.key {
      case "alert_disk_percent": result.diskWarning = value
      case "alert_memory_percent": result.memoryWarning = value
      default:
        if item.key.hasPrefix("alert_project_"), item.key.hasSuffix("_files") {
          let start = item.key.index(item.key.startIndex, offsetBy: "alert_project_".count)
          let end = item.key.index(item.key.endIndex, offsetBy: -"_files".count)
          result.projectOverrides[String(item.key[start..<end]).lowercased()] = Int(value)
        }
      }
    }
    return result
  }

  func projectThreshold(_ name: String) -> Int {
    projectOverrides[name.lowercased()] ?? projectNoteworthy
  }
}
