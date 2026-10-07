import Foundation

enum WatchKind: Codable, Equatable {
  case ciFinished(project: String)
  case serverReachable

  var label: String {
    switch self {
    case .ciFinished(let project): "\(project) CI 완료"
    case .serverReachable: "sol-server 연결 복구"
    }
  }
}

struct WatchTask: Codable, Equatable, Identifiable {
  let id: UUID
  let kind: WatchKind
  let expiresAt: Date

  static let lifetime: TimeInterval = 6 * 60 * 60
}

/// Watches survive an app restart in a small JSON file next to the memory database.
final class WatchTaskStore {
  static let maximumTasks = 10
  private let url: URL

  init(url: URL = MemoryRepository.defaultDatabaseURL.deletingLastPathComponent().appending(path: "watches.json")) {
    self.url = url
  }

  func load() -> [WatchTask] {
    guard let data = try? Data(contentsOf: url) else { return [] }
    return (try? JSONDecoder().decode([WatchTask].self, from: data)) ?? []
  }

  func save(_ tasks: [WatchTask]) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder().encode(tasks).write(to: url, options: .atomic)
  }
}
