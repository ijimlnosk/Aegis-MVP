import Foundation

struct AgentTrace: Codable {
  let request: String
  let action: String
  let result: String
  let createdAt: Date
}

enum LearningMemory {
  private static var fileURL: URL {
    let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appending(path: "Aegis")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder.appending(path: "agent-traces.json")
  }

  static func recent(limit: Int = 6) -> [AgentTrace] {
    guard let data = try? Data(contentsOf: fileURL),
          let values = try? JSONDecoder().decode([AgentTrace].self, from: data) else { return [] }
    return Array(values.suffix(limit))
  }

  static func record(request: String, action: String, result: String) {
    var values = recent(limit: 80)
    values.append(AgentTrace(request: request, action: action, result: result, createdAt: .now))
    guard let data = try? JSONEncoder().encode(Array(values.suffix(80))) else { return }
    try? data.write(to: fileURL, options: .atomic)
  }
}
